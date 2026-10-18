package upstream

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestVerifyRejectsUnknownBinary(t *testing.T) {
	path := filepath.Join(t.TempDir(), "backend")
	data := []byte("не backend")
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(data)
	for _, sum := range []string{"", strings.Repeat("0", 64), hex.EncodeToString(hash[:])} {
		if VerifyBinary(path, sum) == nil {
			t.Fatal("принят неподдерживаемый backend")
		}
	}
}

func TestVerifyBuiltUpstream(t *testing.T) {
	path := os.Getenv("BACKEND_TEST_BINARY")
	if path == "" {
		t.Skip("Нужна отдельно собранная ревизия upstream")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(data)
	if err := VerifyBinary(path, hex.EncodeToString(hash[:])); err != nil {
		t.Fatal(err)
	}
}
