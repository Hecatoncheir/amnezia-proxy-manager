// Package session управляет единственным дочерним движком и его конфигурацией.
package session

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/fullvpn"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/upstream"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/validation"
)

const SocksAddress = "127.0.0.1:1080"
const HTTPAddress = "127.0.0.1:8080"

type Request struct {
	Version            int    `json:"version"`
	ID                 string `json:"requestId"`
	Method             string `json:"method"`
	Family             string `json:"family,omitempty"`
	Binary             string `json:"binary,omitempty"`
	SHA256             string `json:"sha256,omitempty"`
	Configuration      string `json:"configuration,omitempty"`
	SocksPort          *int   `json:"socksPort,omitempty"`
	HTTPPort           *int   `json:"httpPort,omitempty"`
	AllTraffic         bool   `json:"allTraffic,omitempty"`
	KillSwitch         *bool  `json:"killSwitch,omitempty"`
	TunBinary          string `json:"tunBinary,omitempty"`
	PreserveProtection bool   `json:"preserveProtection,omitempty"`
}
type State struct {
	Status          string   `json:"status"`
	Connectivity    string   `json:"connectivity,omitempty"`
	Code            string   `json:"code,omitempty"`
	Traffic         *Traffic `json:"traffic,omitempty"`
	InternetBlocked bool     `json:"internetBlocked"`
}
type running struct {
	ctx       context.Context
	cancel    context.CancelFunc
	done      chan struct{}
	recheck   chan struct{}
	tunExited <-chan error
}
type Manager struct {
	mu          sync.Mutex
	active      *running
	state       State
	publish     func(State)
	verify      func(Request) error
	command     func(context.Context, Request, string) (*exec.Cmd, error)
	check       func(context.Context, string) error
	socks, http string
	blocked     bool
	vpnOnly     bool
	vpnPlans    map[[32]byte]fullvpn.Plan
}

func New(publish func(State)) *Manager {
	return &Manager{state: State{Status: "disconnected"}, publish: publish, verify: verify,
		command: command, check: validation.CheckHTTPS, socks: SocksAddress, http: HTTPAddress}
}
func verify(r Request) error {
	if r.Family == "xray" {
		return upstream.VerifyXrayBinary(r.Binary, r.SHA256)
	}
	if r.Family == "awg" {
		return upstream.VerifyBinary(r.Binary, r.SHA256)
	}
	return errors.New("unsupported_engine")
}
func command(ctx context.Context, r Request, path string) (*exec.Cmd, error) {
	if r.Family == "xray" {
		return upstream.XrayCommand(ctx, r.Binary, path, false)
	}
	return upstream.Command(ctx, upstream.Config{Binary: r.Binary, Profile: path})
}
func (m *Manager) set(state State) {
	m.mu.Lock()
	defer m.mu.Unlock()
	state.InternetBlocked = m.blocked
	m.state = state
	if m.publish != nil {
		m.publish(state)
	}
}
func (m *Manager) Status() State { m.mu.Lock(); defer m.mu.Unlock(); return m.state }
func (m *Manager) Start(r Request) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.validateStart(r); err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(context.Background())
	s := &running{ctx: ctx, cancel: cancel, done: make(chan struct{}), recheck: make(chan struct{}, 1)}
	m.active = s
	m.state = State{Status: "starting", InternetBlocked: m.blocked}
	if m.publish != nil {
		m.publish(m.state)
	}
	go m.run(s, r)
	return nil
}

func (m *Manager) validateStart(r Request) error {
	if m.active != nil {
		return errors.New("already_running")
	}
	if m.vpnOnly && !r.AllTraffic {
		return errors.New("vpn_admin_required")
	}
	if err := r.validate(); err != nil {
		return err
	}
	return m.configurePorts(r)
}

func (r Request) validate() error {
	if err := r.validateConfiguration(); err != nil {
		return err
	}
	return r.validateVPN()
}

func (r Request) validateConfiguration() error {
	if len(r.Configuration) == 0 || len(r.Configuration) > validation.MaxConfig {
		return errors.New("invalid_config")
	}
	if r.Family != "awg" && r.Family != "xray" {
		return errors.New("unsupported_engine")
	}
	return nil
}
func (m *Manager) Stop() error {
	return m.stop(false)
}

func (m *Manager) stop(preserve bool) error {
	if err := m.stopProcess(); err != nil {
		return err
	}
	if preserve {
		return nil
	}
	return m.releaseProtection()
}

func (m *Manager) releaseProtection() error {
	if err := m.clearProtection(); err != nil {
		return err
	}
	m.set(State{Status: "disconnected"})
	return nil
}

func (m *Manager) clearProtection() error {
	if !m.vpnOnly && !m.blocked {
		return nil
	}
	if err := fullvpn.Release(); err != nil {
		return errors.New("vpn_unblock_failed")
	}
	m.mu.Lock()
	m.blocked = false
	m.mu.Unlock()
	return nil
}

func (m *Manager) stopProcess() error {
	m.mu.Lock()
	s := m.active
	if s == nil {
		m.mu.Unlock()
		return nil
	}
	m.state = State{Status: "stopping", InternetBlocked: m.blocked}
	if m.publish != nil {
		m.publish(m.state)
	}
	s.cancel()
	m.mu.Unlock()
	select {
	case <-s.done:
		return nil
	case <-time.After(16 * time.Second):
		return errors.New("stop_timeout")
	}
}
func (m *Manager) run(s *running, r Request) {
	code := "start_failed"
	directory := ""
	var releaseDirectory func()
	defer func() { m.finishRun(s, r, directory, releaseDirectory, code) }()
	prepared, err := m.prepareSystemVPN(s, r)
	directory = prepared.directory
	if err != nil {
		code = err.Error()
		return
	}
	r = prepared.request
	if m.verify(r) != nil {
		code = "untrusted_engine"
		return
	}
	relay, err := newRelays(m.socks, m.http)
	if err != nil {
		code = "port_in_use"
		return
	}
	defer func() { relay.close(); m.reportTraffic(relay) }()
	backendSocks, backendHTTP := relay.addresses()
	config, err := configuration(r, backendSocks, backendHTTP)
	r.Configuration = ""
	if err != nil {
		code = "invalid_config"
		return
	}
	defer clear(config)
	if s.ctx.Err() != nil {
		code = "stopped"
		return
	}
	if directory == "" {
		directory, err = validation.PrivateDirectory()
		if err != nil {
			code = "private_config_failed"
			return
		}
	}
	releaseDirectory, err = ownDirectory(directory)
	if err != nil {
		code = "private_config_failed"
		return
	}
	path := filepath.Join(directory, "profile.conf")
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		code = "private_config_failed"
		return
	}
	_, writeErr := file.Write(config)
	closeErr := file.Close()
	clear(config)
	if writeErr != nil || closeErr != nil {
		code = "private_config_failed"
		return
	}
	if err := m.enableProtection(r, prepared.plan); err != nil {
		code = fullvpn.ProtectionError(err)
		return
	}
	cmd, err := m.command(context.Background(), r, path)
	if err != nil {
		return
	}
	cmd.Stdout, cmd.Stderr = io.Discard, io.Discard
	if err := configureVPNEnvironment(cmd, r, directory); err != nil {
		return
	}
	relay.releaseBackend()
	if s.ctx.Err() != nil {
		code = "stopped"
		return
	}
	kill, err := startProcess(cmd)
	if err != nil {
		return
	}
	exited := make(chan error, 1)
	go func() { exited <- cmd.Wait() }()
	defer kill()
	consumed := false
	defer func() {
		if !consumed {
			signalStop(cmd)
			select {
			case <-exited:
			case <-time.After(2 * time.Second):
				kill()
				<-exited
			}
		}
	}()
	ready := false
	deadline := time.NewTimer(8 * time.Second)
	defer deadline.Stop()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for !ready {
		select {
		case <-s.ctx.Done():
			code = "stopped"
			return
		case <-exited:
			consumed = true
			code = "engine_exited"
			return
		case <-deadline.C:
			code = "listener_timeout"
			return
		case <-ticker.C:
			ready = listenerReady(backendSocks, true) && listenerReady(backendHTTP, false)
		}
	}
	relay.start()
	closeVPN, err := startSystemVPN(s, r, directory, backendSocks, prepared.plan)
	if err != nil {
		code = "vpn_tun_failed"
		return
	}
	defer closeVPN()
	code, consumed = m.monitor(s, exited, relay)
}

func listenerReady(address string, socks bool) bool {
	connection, err := net.DialTimeout("tcp", address, 150*time.Millisecond)
	if err != nil {
		return false
	}
	defer connection.Close()
	if !socks {
		return true
	}
	connection.SetDeadline(time.Now().Add(150 * time.Millisecond))
	connection.Write([]byte{5, 1, 0})
	var answer [2]byte
	_, err = io.ReadFull(connection, answer[:])
	return err == nil && answer == [2]byte{5, 0}
}
func configuration(r Request, socks, http string) ([]byte, error) {
	if r.Family == "awg" {
		// Принимаются только нормализованные Interface/Peer; локальные входы задаёт supervisor.
		for _, line := range strings.Split(r.Configuration, "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "[") && trimmed != "[Interface]" && trimmed != "[Peer]" {
				return nil, errors.New("invalid_config")
			}
			if strings.Contains(strings.ToLower(trimmed), "postup") || strings.Contains(strings.ToLower(trimmed), "postdown") || strings.Contains(trimmed, "$") {
				return nil, errors.New("invalid_config")
			}
		}
		sections, err := upstream.ProxySections(socks, http)
		if err != nil {
			return nil, err
		}
		return []byte(r.Configuration + sections), nil
	}
	var data map[string]any
	if json.Unmarshal([]byte(r.Configuration), &data) != nil {
		return nil, errors.New("invalid_config")
	}
	// Повторно назначаем входы, даже если IPC-клиент передал иные адреса.
	_, socksPort, _ := net.SplitHostPort(socks)
	_, httpPort, _ := net.SplitHostPort(http)
	var sp, hp int
	json.Unmarshal([]byte(socksPort), &sp)
	json.Unmarshal([]byte(httpPort), &hp)
	data["inbounds"] = []any{
		map[string]any{"tag": "manager-socks", "listen": "127.0.0.1", "port": sp, "protocol": "socks", "settings": map[string]any{"auth": "noauth", "udp": r.AllTraffic}},
		map[string]any{"tag": "manager-http", "listen": "127.0.0.1", "port": hp, "protocol": "http", "settings": map[string]any{}},
	}
	data["log"] = map[string]any{"loglevel": "none"}
	delete(data, "api")
	delete(data, "stats")
	encoded, err := json.Marshal(data)
	if len(encoded) > validation.MaxConfig {
		return nil, errors.New("invalid_config")
	}
	// Отделяем буфер от JSON-объектов вызывающей стороны.
	return bytes.Clone(encoded), err
}

func (m *Manager) finishRun(s *running, r Request, directory string, releaseDirectory func(), code string) {
	s.cancel()
	code = m.finishTemporaryProtection(r, code)
	if releaseDirectory != nil {
		releaseDirectory()
	}
	if directory != "" && os.RemoveAll(directory) != nil {
		code = "cleanup_failed"
	}
	m.publishFinished(s, code)
}

func (m *Manager) publishFinished(s *running, code string) {
	m.mu.Lock()
	m.active = nil
	m.state = State{Status: "error", Code: code, InternetBlocked: m.blocked}
	if s.ctx.Err() != nil && code == "stopped" {
		m.state = State{Status: "disconnected", InternetBlocked: m.blocked}
	}
	if m.publish != nil {
		m.publish(m.state)
	}
	close(s.done)
	m.mu.Unlock()
}
