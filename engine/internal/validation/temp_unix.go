//go:build !windows

package validation

import "os"

func privateDirectory() (string, error) {
	return os.MkdirTemp("", "amnezia-config-") // MkdirTemp использует 0700.
}
