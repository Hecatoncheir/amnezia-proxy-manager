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

	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/upstream"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/validation"
)

const SocksAddress = "127.0.0.1:1080"
const HTTPAddress = "127.0.0.1:8080"

type Request struct {
	Version       int    `json:"version"`
	ID            string `json:"requestId"`
	Method        string `json:"method"`
	Family        string `json:"family,omitempty"`
	Binary        string `json:"binary,omitempty"`
	SHA256        string `json:"sha256,omitempty"`
	Configuration string `json:"configuration,omitempty"`
	SocksPort     *int   `json:"socksPort,omitempty"`
	HTTPPort      *int   `json:"httpPort,omitempty"`
}
type State struct {
	Status       string `json:"status"`
	Connectivity string `json:"connectivity,omitempty"`
	Code         string `json:"code,omitempty"`
}
type running struct {
	ctx    context.Context
	cancel context.CancelFunc
	done   chan struct{}
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
	m.state = state
	if m.publish != nil {
		m.publish(state)
	}
}
func (m *Manager) Status() State { m.mu.Lock(); defer m.mu.Unlock(); return m.state }
func (m *Manager) Start(r Request) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.active != nil {
		return errors.New("already_running")
	}
	if err := r.validate(); err != nil {
		return err
	}
	if err := m.configurePorts(r); err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(context.Background())
	s := &running{ctx: ctx, cancel: cancel, done: make(chan struct{})}
	m.active = s
	m.state = State{Status: "starting"}
	if m.publish != nil {
		m.publish(m.state)
	}
	go m.run(s, r)
	return nil
}

func (r Request) validate() error {
	if len(r.Configuration) == 0 || len(r.Configuration) > validation.MaxConfig {
		return errors.New("invalid_config")
	}
	if r.Family != "awg" && r.Family != "xray" {
		return errors.New("unsupported_engine")
	}
	return nil
}
func (m *Manager) Stop() error {
	m.mu.Lock()
	s := m.active
	if s == nil {
		m.mu.Unlock()
		return nil
	}
	m.state = State{Status: "stopping"}
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
	defer func() {
		s.cancel()
		if releaseDirectory != nil {
			releaseDirectory()
		}
		if directory != "" && os.RemoveAll(directory) != nil {
			code = "cleanup_failed"
		}
		m.mu.Lock()
		m.active = nil
		m.state = State{Status: "error", Code: code}
		if s.ctx.Err() != nil && code == "stopped" {
			m.state = State{Status: "disconnected"}
		}
		if m.publish != nil {
			m.publish(m.state)
		}
		close(s.done)
		m.mu.Unlock()
	}()
	if m.verify(r) != nil {
		code = "untrusted_engine"
		return
	}
	config, err := configuration(r, m.socks, m.http)
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
	// Проверяем оба порта до запуска, не принимаем чужой listener за готовность.
	reservations := []net.Listener{}
	for _, address := range []string{m.socks, m.http} {
		listener, err := net.Listen("tcp", address)
		if err != nil {
			for _, l := range reservations {
				l.Close()
			}
			code = "port_in_use"
			return
		}
		reservations = append(reservations, listener)
	}
	defer func() {
		for _, l := range reservations {
			l.Close()
		}
	}()
	directory, err = validation.PrivateDirectory()
	if err != nil {
		code = "private_config_failed"
		return
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
	cmd, err := m.command(context.Background(), r, path)
	if err != nil {
		return
	}
	cmd.Stdout, cmd.Stderr = io.Discard, io.Discard
	for _, l := range reservations {
		l.Close()
	}
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
			ready = listenerReady(m.socks, true) && listenerReady(m.http, false)
		}
	}
	m.set(State{Status: "running", Connectivity: "checking"})
	// Проверка сети не определяет время жизни туннеля и отменяется вместе с ним.
	network := make(chan error, 1)
	go func() {
		ctx, cancel := context.WithTimeout(s.ctx, 25*time.Second)
		defer cancel()
		network <- m.check(ctx, m.socks)
	}()
	for {
		select {
		case <-s.ctx.Done():
			code = "stopped"
			return
		case <-exited:
			consumed = true
			code = "engine_exited"
			return
		case err := <-network:
			connectivity := "verified"
			if err != nil {
				connectivity = "unverified"
			}
			if s.ctx.Err() == nil {
				m.set(State{Status: "running", Connectivity: connectivity})
			}
			network = nil
		}
	}
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
		map[string]any{"tag": "manager-socks", "listen": "127.0.0.1", "port": sp, "protocol": "socks", "settings": map[string]any{"auth": "noauth", "udp": false}},
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
