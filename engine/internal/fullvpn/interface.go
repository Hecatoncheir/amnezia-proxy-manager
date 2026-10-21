package fullvpn

import (
	"errors"
	"net"
	"runtime"
)

func CheckInterfaceAvailable() error {
	if !unixInterface() {
		return nil
	}
	interfaces, err := net.Interfaces()
	if err != nil {
		return errors.New("vpn_tun_failed")
	}
	for _, iface := range interfaces {
		if iface.Name == TunInterfaceName() {
			return errors.New("vpn_interface_busy")
		}
	}
	return nil
}

func unixInterface() bool { return runtime.GOOS == "linux" || runtime.GOOS == "darwin" }
