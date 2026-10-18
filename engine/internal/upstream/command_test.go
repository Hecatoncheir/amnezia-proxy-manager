package upstream

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
)

func TestCommand(t *testing.T) {
	root := t.TempDir()
	cfg := Config{filepath.Join(root, "wireproxy"), filepath.Join(root, "profile with spaces.conf")}
	t.Setenv("WIREPROXY_ADMIN", "0.0.0.0:9090")
	cmd, err := Command(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	if cmd.Args[2] != cfg.Profile {
		t.Fatal("путь профиля изменён")
	}
	if len(cmd.Args) != 4 || cmd.Args[1] != "--config" || cmd.Args[3] != "--silent" {
		t.Fatal("неверный контракт CLI")
	}
	check, err := ConfigTestCommand(context.Background(), cfg)
	if err != nil || check.Args[len(check.Args)-1] != "--configtest" {
		t.Fatal("отсутствует предварительная проверка конфигурации")
	}
	for _, entry := range cmd.Env {
		if strings.HasPrefix(strings.ToUpper(entry), "WIREPROXY_") {
			t.Fatal("веб-панель может включиться из окружения")
		}
	}
	sections, err := ProxySections("127.0.0.1:1080", "[::1]:8080")
	if err != nil || !strings.Contains(sections, "[Socks5]\nBindAddress = 127.0.0.1:1080") ||
		!strings.Contains(sections, "[http]\nBindAddress = [::1]:8080") {
		t.Fatal("неверные секции прокси")
	}
	for _, address := range []string{"0.0.0.0:1080", "localhost:1080", "127.0.0.1:0", "[::]:1080", "127.0.0.1:65536"} {
		if _, err := ProxySections(address, "127.0.0.1:8080"); err == nil {
			t.Errorf("принят адрес %s", address)
		}
	}
	if _, err := ProxySections("127.0.0.1:1080", "127.0.0.1:1080"); err == nil {
		t.Fatal("приняты совпадающие порты")
	}
}
