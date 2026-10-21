package fullvpn

import (
	"errors"
	"strings"
)

func nftBinary() (string, error) { return systemBinary("/usr/sbin/nft", "/sbin/nft", "/usr/bin/nft") }

func IsProtected() bool {
	path, err := nftBinary()
	if err != nil {
		return false
	}
	exists, err := nftExists(runSystemCommand, path)
	return err != nil || exists
}

func nftExists(run commandRunner, path string) (bool, error) {
	output, err := run(path, []string{"list", "tables"}, "")
	return strings.Contains(output, "table inet "+nftTable+"\n"), err
}

func Protect(_ string, plan Plan) error {
	path, err := nftBinary()
	if err != nil {
		return err
	}
	return applyNFT(runSystemCommand, path, plan)
}

func applyNFT(run commandRunner, path string, plan Plan) error {
	exists, err := nftExists(run, path)
	if err != nil {
		return errors.New("vpn_firewall_failed")
	}
	rules, err := nftRules(plan, exists)
	if err != nil {
		return err
	}
	// Один пакет nft применяет новые правила атомарно, без снятия защиты между повторами.
	if _, err := run(path, []string{"-f", "-"}, rules); err != nil {
		return errors.New("vpn_firewall_failed")
	}
	return nil
}

func AllowTunnel() error { return nil }

func Release() error {
	if !Privileged() {
		return errors.New("vpn_admin_required")
	}
	path, err := nftBinary()
	if err != nil {
		return err
	}
	exists, err := nftExists(runSystemCommand, path)
	if err != nil {
		return err
	}
	if !exists {
		return nil
	}
	_, err = runSystemCommand(path, []string{"delete", "table", "inet", nftTable}, "")
	return err
}
