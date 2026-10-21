//go:build !windows && !linux && !darwin

package fullvpn

import (
	"errors"
	"io"
)

func Bridge(io.Reader, io.Writer) error       { return errors.New("vpn_platform_unsupported") }
func Pipe(string) (io.ReadWriteCloser, error) { return nil, errors.New("vpn_platform_unsupported") }
