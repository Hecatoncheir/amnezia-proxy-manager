package session

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Дочерний процесс имитирует только listeners; реальный VPN проверяется отдельно.
func TestEngineFixture(t *testing.T) {
	if os.Getenv("SESSION_FIXTURE") != "1" {
		return
	}
	path := os.Args[len(os.Args)-1]
	data, err := os.ReadFile(path)
	if err != nil {
		os.Exit(10)
	}
	addresses := []string{}
	if len(data) > 0 && data[0] == '{' {
		var cfg map[string]any
		json.Unmarshal(data, &cfg)
		for _, v := range cfg["inbounds"].([]any) {
			entry := v.(map[string]any)
			addresses = append(addresses, net.JoinHostPort("127.0.0.1", strconv.Itoa(int(entry["port"].(float64)))))
		}
	} else {
		for _, v := range regexp.MustCompile(`BindAddress = ([^\r\n]+)`).FindAllStringSubmatch(string(data), -1) {
			addresses = append(addresses, v[1])
		}
	}
	if len(addresses) != 2 {
		os.Exit(11)
	}
	for i, address := range addresses {
		listener, err := net.Listen("tcp", address)
		if err != nil {
			os.Exit(12)
		}
		go func(index int) {
			for {
				c, err := listener.Accept()
				if err != nil {
					return
				}
				go func() {
					defer c.Close()
					c.SetDeadline(time.Now().Add(time.Second))
					if index == 0 {
						buf := make([]byte, 3)
						io.ReadFull(c, buf)
						c.Write([]byte{5, 0})
					}
				}()
			}
		}(i)
	}
	if os.Getenv("SESSION_CRASH") == "1" {
		time.Sleep(500 * time.Millisecond)
		os.Exit(9)
	}
	select {}
}
func freeAddress(t *testing.T) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().String()
}
func testManager(t *testing.T) (*Manager, *string) {
	t.Helper()
	m := New(nil)
	m.socks = freeAddress(t)
	m.http = freeAddress(t)
	for m.socks == m.http {
		m.http = freeAddress(t)
	}
	lastPath := ""
	m.verify = func(Request) error { return nil }
	m.check = func(context.Context, string) error { return nil }
	m.command = func(_ context.Context, _ Request, path string) (*exec.Cmd, error) {
		lastPath = path
		cmd := exec.Command(os.Args[0], "-test.run=^TestEngineFixture$", "--", path)
		cmd.Env = append(os.Environ(), "SESSION_FIXTURE=1")
		return cmd, nil
	}
	t.Cleanup(func() { m.Stop() })
	return m, &lastPath
}
func waitState(t *testing.T, m *Manager, status string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		state := m.Status()
		if state.Status == status {
			return
		}
		if state.Status == "error" && status != "error" {
			t.Fatalf("сбой: %s", state.Code)
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("не получен статус %s: %+v", status, m.Status())
}
func TestHundredStartStopCycles(t *testing.T) {
	m, path := testManager(t)
	for i := 0; i < 100; i++ {
		request := Request{Family: "xray", Configuration: `{"outbounds":[]}`}
		if i%2 == 0 {
			request = Request{Family: "awg", Configuration: "[Interface]\nPrivateKey = test\n[Peer]\nPublicKey = test\n"}
		}
		if err := m.Start(request); err != nil {
			t.Fatal(err)
		}
		waitState(t, m, "running")
		if err := m.Start(request); err == nil {
			t.Fatal("двойной start разрешён")
		}
		if err := m.Stop(); err != nil {
			t.Fatal(err)
		}
		if m.Status().Status != "disconnected" {
			t.Fatal(m.Status())
		}
		if _, err := os.Stat(filepath.Dir(*path)); !os.IsNotExist(err) {
			t.Fatal("конфигурация осталась")
		}
		for _, address := range []string{m.socks, m.http} {
			listener, err := net.Listen("tcp", address)
			if err != nil {
				t.Fatal("порт остался занят")
			}
			listener.Close()
		}
	}
	if err := m.Stop(); err != nil {
		t.Fatal("повторный stop", err)
	}
}
func TestOccupiedPortAndCancellation(t *testing.T) {
	m, _ := testManager(t)
	listener, err := net.Listen("tcp", m.http)
	if err != nil {
		t.Fatal(err)
	}
	m.Start(Request{Family: "xray", Configuration: `{}`})
	waitState(t, m, "error")
	if m.Status().Code != "port_in_use" {
		t.Fatal(m.Status())
	}
	listener.Close()
	m.Start(Request{Family: "xray", Configuration: `{}`})
	if err := m.Stop(); err != nil {
		t.Fatal(err)
	}
	if m.Status().Status != "disconnected" {
		t.Fatal(m.Status())
	}
}
func TestRejectUntrustedAndHandleCrash(t *testing.T) {
	m, _ := testManager(t)
	m.verify = func(Request) error { return errors.New("secret-value") }
	m.Start(Request{Family: "xray", Configuration: `{}`})
	waitState(t, m, "error")
	if m.Status().Code != "untrusted_engine" {
		t.Fatal(m.Status())
	}
	m.verify = func(Request) error { return nil }
	original := m.command
	m.command = func(ctx context.Context, r Request, p string) (*exec.Cmd, error) {
		cmd, err := original(ctx, r, p)
		cmd.Env = append(cmd.Env, "SESSION_CRASH=1")
		return cmd, err
	}
	m.Start(Request{Family: "xray", Configuration: `{}`})
	waitState(t, m, "running")
	waitState(t, m, "error")
	if m.Status().Code != "engine_exited" {
		t.Fatal(m.Status())
	}
}
func TestIPCVersionAndRedaction(t *testing.T) {
	input := `{"version":2,"requestId":"bad","method":"hello","configuration":"secret-value"}` + "\n" +
		`{"version":1,"requestId":"1","method":"status"}` + "\n" +
		`{"version":1,"requestId":"2","method":"hello"}` + "\n" +
		`{"version":1,"requestId":"3","method":"status"}` + "\n" +
		`{"version":1,"requestId":"4","method":"stop"}` + "\n"
	var output strings.Builder
	if serve(strings.NewReader(input), &output) != nil {
		t.Fatal("IPC failed")
	}
	if strings.Contains(output.String(), "secret-value") {
		t.Fatal("секрет в IPC")
	}
	if !strings.Contains(output.String(), "handshake_required") || !strings.Contains(output.String(), "disconnected") {
		t.Fatal("неверное согласование IPC")
	}
	if serve(strings.NewReader(strings.Repeat("a", MaxLine+1)), io.Discard) == nil {
		t.Fatal("нет лимита строки")
	}
}
