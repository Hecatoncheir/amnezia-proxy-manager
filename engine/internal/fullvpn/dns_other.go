//go:build !darwin || !cgo

package fullvpn

import (
	"errors"
	"runtime"
)

func ConfigureDNS() (func(), error) {
	if runtime.GOOS == "darwin" {
		return nil, errors.New("vpn_dns_unavailable")
	}
	return func() {}, nil
}
