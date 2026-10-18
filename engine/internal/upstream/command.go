// Package upstream описывает запуск отдельно собранного awg-wireproxy.
package upstream

import (
	"context"
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

const Revision = "02588433b6328171b594d76f3f16bd3404258a83"

type Config struct {
	Binary  string
	Profile string
}

func validateAddress(address string) error {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return errors.New("некорректный адрес прокси")
	}
	ip := net.ParseIP(host)
	number, err := strconv.Atoi(port)
	if ip == nil || !ip.IsLoopback() || err != nil || number < 1 || number > 65535 {
		return errors.New("разрешены только loopback IP и порты 1–65535")
	}
	return nil
}

// Command не запускает процесс и не читает профиль. Оболочка не используется.
func Command(ctx context.Context, cfg Config) (*exec.Cmd, error) {
	if !filepath.IsAbs(cfg.Binary) || !filepath.IsAbs(cfg.Profile) {
		return nil, errors.New("нужны абсолютные пути движка и профиля")
	}
	// Profile — только сгенерированная менеджером конфигурация, не сырой импорт.
	cmd := exec.CommandContext(ctx, cfg.Binary, "--config", cfg.Profile, "--silent")
	// Переменные upstream не должны неявно включать веб-панель.
	for _, entry := range os.Environ() {
		key, _, _ := strings.Cut(entry, "=")
		if !strings.HasPrefix(strings.ToUpper(key), "WIREPROXY_") {
			cmd.Env = append(cmd.Env, entry)
		}
	}
	return cmd, nil
}

// ConfigTestCommand проверяет сгенерированную конфигурацию без запуска туннеля.
func ConfigTestCommand(ctx context.Context, cfg Config) (*exec.Cmd, error) {
	cmd, err := Command(ctx, cfg)
	if err != nil {
		return nil, err
	}
	cmd.Args = append(cmd.Args, "--configtest")
	return cmd, nil
}

// ProxySections добавляется к разрешённым секциям профиля после разбора M2.
// Сырые конфигурации, WGConfig, PostUp/PostDown и секции upstream не импортируются.
func ProxySections(socks, http string) (string, error) {
	if err := validateAddress(socks); err != nil {
		return "", err
	}
	if err := validateAddress(http); err != nil {
		return "", err
	}
	if socks == http {
		return "", errors.New("порты прокси должны различаться")
	}
	return "\n[Socks5]\nBindAddress = " + socks + "\n\n[http]\nBindAddress = " + http + "\n", nil
}
