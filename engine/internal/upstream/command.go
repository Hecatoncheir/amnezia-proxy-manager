// Package upstream описывает запуск отдельно собранного amnezia-proxy.
package upstream

import (
	"context"
	"errors"
	"net"
	"os/exec"
	"path/filepath"
	"strconv"
)

const Revision = "f5a7912dba8b128ae5c1a3f68a06be7c1668b908"

type Config struct {
	Binary  string
	Profile string
	SOCKS   string
	HTTP    string
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
	if err := validateAddress(cfg.SOCKS); err != nil {
		return nil, err
	}
	if err := validateAddress(cfg.HTTP); err != nil {
		return nil, err
	}
	if cfg.SOCKS == cfg.HTTP {
		return nil, errors.New("порты прокси должны различаться")
	}
	return exec.CommandContext(ctx, cfg.Binary, "-config", cfg.Profile,
		"-socks-listen", cfg.SOCKS, "-http-listen", cfg.HTTP), nil
}
