//go:build linux || darwin

package fullvpn

import (
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestUnixSocketPath(t *testing.T) {
	if !validSocketPath("/tmp/apm-vpn-test/control.sock") {
		t.Fatal("обычный путь отклонён")
	}
	for _, path := range []string{"/etc/control.sock", "/tmp/control.sock", "/tmp/apm-vpn-test/../control.sock", "/tmp/apm-vpn-test/other.sock"} {
		if validSocketPath(path) {
			t.Fatalf("опасный путь принят: %s", path)
		}
	}
}

func TestUnixPeerCredentials(t *testing.T) {
	listener, err := net.Listen("unix", filepath.Join(t.TempDir(), "control.sock"))
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	result := make(chan error, 1)
	go func() {
		c, err := listener.Accept()
		if err != nil {
			result <- err
			return
		}
		defer c.Close()
		result <- rootPeer(c)
	}()
	c, err := net.Dial("unix", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	peerError := <-result
	if (peerError == nil) != (os.Geteuid() == 0) {
		t.Fatalf("UID не проверен: %v", peerError)
	}
}

func TestUnixEnvironmentIsolated(t *testing.T) {
	t.Setenv("XRAY_LOCATION_CONFDIR", "untrusted")
	t.Setenv("SING_BOX_CONFIG", "untrusted")
	environment, err := Environment("/private/session")
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range environment {
		if strings.Contains(value, "untrusted") {
			t.Fatal(value)
		}
	}
}
