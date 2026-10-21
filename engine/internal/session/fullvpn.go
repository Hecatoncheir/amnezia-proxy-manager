package session

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/fullvpn"
)

func (r Request) validateVPN() error {
	if !r.AllTraffic {
		return nil
	}
	if !fullvpn.Supported() {
		return errors.New("vpn_platform_unsupported")
	}
	if !fullvpn.Privileged() {
		return errors.New("vpn_admin_required")
	}
	if r.TunBinary == "" {
		return errors.New("vpn_runtime_missing")
	}
	return fullvpn.ValidateProfile(r.Family, r.Configuration)
}

func trustedVPNBinary(family string) string {
	return fullvpn.BinaryHash(family)
}

func copyVerified(source, target, expected string) error {
	if !filepath.IsAbs(source) {
		return errors.New("untrusted_engine")
	}
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	actual, err := copyAndHash(input, target)
	if err != nil {
		return err
	}
	if actual != expected {
		return errors.New("untrusted_engine")
	}
	return os.Chmod(target, 0700)
}

func copyAndHash(input io.Reader, target string) (string, error) {
	output, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return "", err
	}
	hash := sha256.New()
	_, copyErr := io.Copy(io.MultiWriter(output, hash), io.LimitReader(input, 128*1024*1024+1))
	return hex.EncodeToString(hash.Sum(nil)), errors.Join(copyErr, output.Close())
}

func privateVPNBinaries(r Request, directory string) (Request, error) {
	backend := filepath.Join(directory, fullvpn.BackendName())
	if err := copyVerified(r.Binary, backend, trustedVPNBinary(r.Family)); err != nil {
		return r, err
	}
	tun := filepath.Join(directory, fullvpn.TunBinaryName())
	if err := copyVerified(r.TunBinary, tun, fullvpn.BinaryHash("tun")); err != nil {
		return r, err
	}
	r.Binary, r.TunBinary = backend, tun
	return r, nil
}

type vpnPreparation struct {
	request   Request
	plan      fullvpn.Plan
	directory string
}

func (m *Manager) prepareSystemVPN(s *running, r Request) (vpnPreparation, error) {
	result := vpnPreparation{request: r}
	if !r.AllTraffic {
		return result, nil
	}
	if err := fullvpn.CheckInterfaceAvailable(); err != nil {
		return result, err
	}
	plan, err := m.vpnPlan(s, r)
	if err != nil {
		return result, errors.New("vpn_endpoint_failed")
	}
	result.plan = plan
	result.request.Configuration = plan.Configuration
	return prepareVPNFiles(result)
}

func prepareVPNFiles(result vpnPreparation) (vpnPreparation, error) {
	var err error
	result.directory, err = fullvpn.ProtectedDirectory()
	if err != nil {
		return result, errors.New("private_config_failed")
	}
	result.request, err = privateVPNBinaries(result.request, result.directory)
	if err != nil {
		return result, errors.New("untrusted_engine")
	}
	return result, nil
}

func (m *Manager) enableProtection(r Request, plan fullvpn.Plan) error {
	if !r.KillSwitchEnabled() {
		return nil
	}
	m.mu.Lock()
	m.blocked = true
	m.mu.Unlock()
	return fullvpn.Protect(r.Binary, plan)
}

func startSystemVPN(s *running, r Request, directory, socks string, plan fullvpn.Plan) (func(), error) {
	if !r.AllTraffic {
		return func() {}, nil
	}
	vpn, err := startVPN(s.ctx, r, directory, socks, plan)
	if err != nil {
		return nil, err
	}
	s.tunExited = vpn.exited
	return vpn.close, nil
}

func (m *Manager) vpnPlan(s *running, r Request) (fullvpn.Plan, error) {
	key := sha256.Sum256([]byte(r.Family + r.Configuration))
	if plan, ok := m.vpnPlans[key]; ok {
		return plan, nil
	}
	ctx, cancel := context.WithTimeout(s.ctx, 10*time.Second)
	defer cancel()
	plan, err := fullvpn.Prepare(ctx, r.Family, r.Configuration)
	if err == nil {
		m.vpnPlans = map[[32]byte]fullvpn.Plan{key: plan}
	}
	return plan, err
}

func configureVPNEnvironment(cmd *exec.Cmd, r Request, directory string) error {
	if !r.AllTraffic {
		return nil
	}
	environment, err := fullvpn.Environment(directory)
	if err != nil {
		return err
	}
	cmd.Env = environment
	cmd.Dir = directory
	return nil
}

type vpnProcess struct {
	cmd    *exec.Cmd
	exited chan error
	kill   func()
}

func vpnInterfaceReady() bool {
	iface, err := net.InterfaceByName(fullvpn.TunInterfaceName())
	if err != nil {
		return false
	}
	if iface.Flags&net.FlagUp == 0 {
		return false
	}
	addresses, err := iface.Addrs()
	if err != nil {
		return false
	}
	return hasVPNAddresses(addresses)
}

func hasVPNAddresses(addresses []net.Addr) bool {
	present := make(map[string]bool)
	for _, address := range addresses {
		present[address.String()] = true
	}
	return present["172.31.255.1/30"] && present["fdfe:dcba:9876::1/126"]
}

func startVPN(ctx context.Context, r Request, directory, socks string, plan fullvpn.Plan) (*vpnProcess, error) {
	path, err := writeTUNConfiguration(directory, socks, plan)
	if err != nil {
		return nil, err
	}
	cmd := exec.Command(r.TunBinary, "run", "-c", path)
	if err := configureVPNEnvironment(cmd, r, directory); err != nil {
		return nil, err
	}
	cmd.Stdout, cmd.Stderr = io.Discard, io.Discard
	kill, err := startTunnelProcess(cmd)
	if err != nil {
		return nil, err
	}
	process := &vpnProcess{cmd: cmd, exited: make(chan error, 1), kill: kill}
	go func() { cmd.Wait(); close(process.exited) }()
	if err := process.ready(ctx, r.KillSwitchEnabled()); err != nil {
		process.close()
		return nil, err
	}
	return process, nil
}

func writeTUNConfiguration(directory, socks string, plan fullvpn.Plan) (string, error) {
	data, err := fullvpn.Configuration(socks, plan.Exclude)
	if err != nil {
		return "", err
	}
	path := filepath.Join(directory, "tun.json")
	return path, os.WriteFile(path, data, 0600)
}

func (r Request) KillSwitchEnabled() bool {
	return r.AllTraffic && (r.KillSwitch == nil || *r.KillSwitch)
}

func (p *vpnProcess) ready(ctx context.Context, protect bool) error {
	if err := p.waitInterface(ctx); err != nil {
		return err
	}
	if protect {
		return fullvpn.AllowTunnel()
	}
	return nil
}

func (p *vpnProcess) waitInterface(ctx context.Context) error {
	timer := time.NewTimer(12 * time.Second)
	defer timer.Stop()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		ready, err := p.interfaceStep(ctx, timer.C, ticker.C)
		if err != nil {
			return err
		}
		if ready {
			return nil
		}
	}
}

func (p *vpnProcess) interfaceStep(ctx context.Context, timeout, tick <-chan time.Time) (bool, error) {
	select {
	case <-ctx.Done():
		return false, ctx.Err()
	case <-p.exited:
		return false, errors.New("vpn_tun_exited")
	case <-timeout:
		return false, errors.New("vpn_tun_timeout")
	case <-tick:
		return vpnInterfaceReady(), nil
	}
}

func (p *vpnProcess) close() {
	select {
	case <-p.exited:
		p.kill()
		return
	default:
	}
	signalTunnelStop(p.cmd)
	select {
	case <-p.exited:
	case <-time.After(2 * time.Second):
		p.kill()
		<-p.exited
	}
	p.kill()
}
