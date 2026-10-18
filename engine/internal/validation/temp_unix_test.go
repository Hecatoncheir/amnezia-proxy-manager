//go:build !windows

package validation

import (
	"os"
	"testing"
)

func checkPermissions(t *testing.T, directory, file string) {
	for path, expected := range map[string]os.FileMode{directory: 0700, file: 0600} {
		info, err := os.Stat(path)
		if err != nil || info.Mode().Perm() != expected {
			t.Fatal("неверные права временных данных")
		}
	}
}
