package upstream

import (
	"context"
	"path/filepath"
	"testing"
)

func TestCommand(t *testing.T) {
	root := t.TempDir()
	cfg := Config{filepath.Join(root, "awg-proxy"), filepath.Join(root, "profile with spaces.conf"), "127.0.0.1:1080", "127.0.0.1:8080"}
	cmd, err := Command(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	if cmd.Args[2] != cfg.Profile {
		t.Fatal("путь профиля изменён")
	}
	for _, address := range []string{"0.0.0.0:1080", "localhost:1080", "127.0.0.1:0", "[::]:1080", "127.0.0.1:65536"} {
		cfg.SOCKS = address
		if _, err := Command(context.Background(), cfg); err == nil {
			t.Errorf("принят адрес %s", address)
		}
	}
}
