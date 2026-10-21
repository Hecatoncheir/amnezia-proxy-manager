package fullvpn

import (
	"errors"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const pfctl = "/sbin/pfctl"

func IsProtected() bool {
	output, err := runSystemCommand(pfctl, []string{"-a", pfAnchor, "-sr"}, "")
	return err == nil && strings.Contains(output, pfLabel)
}

func Protect(_ string, plan Plan) error {
	rules, err := pfRules(plan)
	if err != nil {
		return err
	}
	if err := secureStateRoot(); err != nil {
		return err
	}
	return applyPF(runSystemCommand, rules)
}

func applyPF(run commandRunner, rules string) error {
	if err := checkPFLayout(run); err != nil {
		return err
	}
	if err := loadPFRules(run, rules); err != nil {
		return err
	}
	if err := enablePF(run); err != nil {
		return err
	}
	// Старые состояния PF иначе могли бы пропускать соединения мимо новых правил.
	if _, err := run(pfctl, []string{"-F", "states"}, ""); err != nil {
		return errors.New("vpn_firewall_failed")
	}
	return nil
}

func loadPFRules(run commandRunner, rules string) error {
	if _, err := run(pfctl, []string{"-a", pfAnchor, "-nf", "-"}, rules); err != nil {
		return errors.New("vpn_firewall_failed")
	}
	if _, err := run(pfctl, []string{"-a", pfAnchor, "-f", "-"}, rules); err != nil {
		return errors.New("vpn_firewall_failed")
	}
	return nil
}

func checkPFLayout(run commandRunner) error {
	output, err := run(pfctl, []string{"-sr"}, "")
	if err != nil {
		return errors.New("vpn_firewall_failed")
	}
	if err := compatiblePFRoot(output); err != nil {
		return err
	}
	output, err = run(pfctl, []string{"-a", "com.apple", "-s", "Anchors"}, "")
	if err != nil {
		return errors.New("vpn_firewall_failed")
	}
	if err := compatiblePFAnchors(output); err != nil {
		return err
	}
	return checkPFSkippedInterfaces(run)
}

func compatiblePFRoot(output string) error {
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, `anchor "com.apple/*"`) {
			return nil
		}
		if isQuickPass(line) {
			return errors.New("vpn_firewall_conflict")
		}
	}
	return errors.New("vpn_firewall_conflict")
}

func isQuickPass(line string) bool {
	return strings.HasPrefix(line, "pass ") && strings.Contains(line, " quick ")
}

func compatiblePFAnchors(output string) error {
	ours := strings.TrimPrefix(pfAnchor, "com.apple/")
	for _, line := range strings.Split(output, "\n") {
		name := strings.Trim(strings.TrimSpace(line), `"`)
		name = strings.TrimPrefix(name, "com.apple/")
		if name != "" && name < ours {
			return errors.New("vpn_firewall_conflict")
		}
	}
	return nil
}

func checkPFSkippedInterfaces(run commandRunner) error {
	interfaces, err := net.Interfaces()
	if err != nil {
		return err
	}
	for _, iface := range interfaces {
		if err := checkPFInterface(run, iface.Name); err != nil {
			return err
		}
	}
	return nil
}

func checkPFInterface(run commandRunner, name string) error {
	if name == "lo0" || name == TunInterfaceName() {
		return nil
	}
	output, err := run(pfctl, []string{"-i", name, "-v", "-s", "Interfaces"}, "")
	if err != nil {
		return errors.New("vpn_firewall_failed")
	}
	if strings.Contains(strings.ToLower(output), "skip") {
		return errors.New("vpn_firewall_conflict")
	}
	return nil
}

var pfToken = regexp.MustCompile(`Token\s*:\s*([0-9]+)`)

func enablePF(run commandRunner) error {
	if pfReferenceExists(run) {
		return nil
	}
	output, err := run(pfctl, []string{"-E"}, "")
	if err != nil {
		return errors.New("vpn_firewall_failed")
	}
	token := pfToken.FindStringSubmatch(output)
	if len(token) != 2 {
		return errors.New("vpn_firewall_failed")
	}
	return os.WriteFile(filepath.Join(stateRoot, "pf.token"), []byte(token[1]), 0600)
}

func pfReferenceExists(run commandRunner) bool {
	if _, err := os.Stat(filepath.Join(stateRoot, "pf.token")); err != nil {
		return false
	}
	output, err := run(pfctl, []string{"-si"}, "")
	return err == nil && strings.Contains(output, "Status: Enabled")
}

func AllowTunnel() error { return nil }

func Release() error {
	if !Privileged() {
		return errors.New("vpn_admin_required")
	}
	if _, err := runSystemCommand(pfctl, []string{"-a", pfAnchor, "-F", "rules"}, ""); err != nil {
		return err
	}
	return releasePFReference(runSystemCommand)
}

func releasePFReference(run commandRunner) error {
	path := filepath.Join(stateRoot, "pf.token")
	token, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if !regexp.MustCompile(`^[0-9]+$`).Match(token) {
		return errors.New("vpn_unblock_failed")
	}
	if _, err := run(pfctl, []string{"-X", string(token)}, ""); err != nil {
		return err
	}
	return os.Remove(path)
}
