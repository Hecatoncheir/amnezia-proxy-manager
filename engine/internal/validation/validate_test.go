package validation

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPrivateDirectory(t *testing.T) {
	path, err := privateDirectory()
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(path)
	file := filepath.Join(path, "profile.conf")
	if err := os.WriteFile(file, []byte("тест"), 0600); err != nil {
		t.Fatal(err)
	}
	checkPermissions(t, path, file)
}

func TestNativeConfigValidation(t *testing.T) {
	binary := os.Getenv("BACKEND_TEST_BINARY")
	if binary == "" {
		t.Skip("Нужен проверенный бинарник backend")
	}
	data, err := os.ReadFile(binary)
	if err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(data)
	sum := hex.EncodeToString(hash[:])
	const config = `[Interface]
Address = 10.200.200.2/32
PrivateKey = uCTIK+56CPyCvwJxmU5dBfuyJvPuSXAq1FzHdnIxe1Q=
DNS = 10.200.200.1
[Peer]
PublicKey = QP+A67Z2UBrMgvNIdHv8gPel5URWNLS4B3ZQ2hQIZlg=
Endpoint = 127.0.0.1:9
AllowedIPs = 0.0.0.0/0
[Socks5]
BindAddress = 127.0.0.1:1080
`
	if err := Validate(binary, sum, strings.NewReader(config)); err != nil {
		t.Fatal(err)
	}
	invalid := strings.ReplaceAll(config, "uCTIK+56CPyCvwJxmU5dBfuyJvPuSXAq1FzHdnIxe1Q=", "SECRET-BAD-KEY")
	if err := Validate(binary, sum, strings.NewReader(invalid)); err == nil || strings.Contains(err.Error(), "SECRET-BAD-KEY") {
		t.Fatal("неверный ключ принят или попал в ошибку")
	}
	if err := Validate(binary, sum, strings.NewReader(strings.Repeat("x", MaxConfig+1))); err == nil {
		t.Fatal("превышение размера принято")
	}
}
