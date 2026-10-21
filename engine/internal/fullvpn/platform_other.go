//go:build !windows && !linux && !darwin

package fullvpn

import "errors"

func Environment(string) ([]string, error) { return nil, errors.New("vpn_platform_unsupported") }

func IsProtected() bool     { return false }
func Lock() (func(), error) { return nil, errors.New("vpn_platform_unsupported") }

func Supported() bool                     { return false }
func Privileged() bool                    { return false }
func Protect(string, Plan) error          { return errors.New("vpn_platform_unsupported") }
func AllowTunnel() error                  { return errors.New("vpn_platform_unsupported") }
func Release() error                      { return nil }
func ProtectedDirectory() (string, error) { return "", errors.New("vpn_platform_unsupported") }
