package session

import (
	"net"
	"strconv"
	"testing"
)

func portNumber(t *testing.T, address string) *int {
	t.Helper()
	_, text, err := net.SplitHostPort(address)
	if err != nil {
		t.Fatal(err)
	}
	port, err := strconv.Atoi(text)
	if err != nil {
		t.Fatal(err)
	}
	return &port
}

func TestCustomPorts(t *testing.T) {
	for _, family := range []string{"awg", "xray"} {
		t.Run(family, func(t *testing.T) {
			m, _ := testManager(t)
			socks, http := m.socks, m.http
			m.socks, m.http = SocksAddress, HTTPAddress
			config := "[Interface]\nPrivateKey = test\n[Peer]\nPublicKey = test\n"
			if family == "xray" {
				config = `{"outbounds":[]}`
			}
			request := Request{Family: family, Configuration: config, SocksPort: portNumber(t, socks), HTTPPort: portNumber(t, http)}
			if err := m.Start(request); err != nil {
				t.Fatal(err)
			}
			waitState(t, m, "running")
			if m.socks != socks || m.http != http {
				t.Fatal("выбранные порты не применены")
			}
			if err := m.Stop(); err != nil {
				t.Fatal(err)
			}
			for _, address := range []string{socks, http} {
				listener, err := net.Listen("tcp", address)
				if err != nil {
					t.Fatal("порт не освобождён", err)
				}
				listener.Close()
			}
		})
	}
}

func TestRejectInvalidPorts(t *testing.T) {
	for _, port := range []int{-1, 0, 65536} {
		m := New(nil)
		err := m.Start(Request{Family: "xray", Configuration: `{}`, SocksPort: &port})
		if err == nil || err.Error() != "invalid_ports" {
			t.Fatal("принят неверный порт", port)
		}
		if m.Status().Status != "disconnected" {
			t.Fatal("движок начал запуск")
		}
	}

	m := New(nil)
	port := 8080
	if err := m.Start(Request{Family: "xray", Configuration: `{}`, SocksPort: &port, HTTPPort: &port}); err == nil {
		t.Fatal("приняты одинаковые порты")
	}
	if m.socks != SocksAddress || m.http != HTTPAddress {
		t.Fatal("изменены прежние настройки")
	}
}
