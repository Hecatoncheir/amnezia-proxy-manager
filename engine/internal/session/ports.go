package session

import (
	"errors"
	"net"
	"strconv"

	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/upstream"
)

// Адрес задаёт только менеджер: пользователь выбирает номер порта, а не сетевой интерфейс.
func portAddress(port *int, fallback string) (string, error) {
	if port == nil {
		return fallback, nil
	}
	if *port < 1 || *port > 65535 {
		return "", errors.New("invalid_ports")
	}
	return net.JoinHostPort("127.0.0.1", strconv.Itoa(*port)), nil
}

func (m *Manager) configurePorts(r Request) error {
	socks, err := portAddress(r.SocksPort, m.socks)
	if err != nil {
		return err
	}
	http, err := portAddress(r.HTTPPort, m.http)
	if err != nil {
		return err
	}
	if _, err := upstream.ProxySections(socks, http); err != nil {
		return errors.New("invalid_ports")
	}
	m.socks, m.http = socks, http
	return nil
}
