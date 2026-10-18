package upstream

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestXrayCommand(t *testing.T) {
	root := t.TempDir()
	t.Setenv("XRAY_LOCATION_CONFIG", "C:/unexpected")
	command, err := XrayCommand(context.Background(), filepath.Join(root, "xray.exe"), filepath.Join(root, "профиль.json"), true)
	if err != nil {
		t.Fatal(err)
	}
	if command.Args[len(command.Args)-1] != "-test" {
		t.Fatal("нет проверки конфигурации")
	}
	for _, entry := range command.Env {
		if entry == "XRAY_LOCATION_CONFIG=C:/unexpected" {
			t.Fatal("унаследован чужой конфиг")
		}
	}
	if VerifyXrayBinary(filepath.Join(root, "missing"), "invalid") == nil {
		t.Fatal("непроверенный бинарник принят")
	}
}

func TestPublishedXray(t *testing.T) {
	path := os.Getenv("XRAY_TEST_BINARY")
	if path == "" {
		t.Skip("нужен релизный Xray")
	}
	if err := VerifyXrayBinary(path, xrayHashes["windows/amd64"]); err != nil {
		t.Fatal(err)
	}
}
