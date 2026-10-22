//go:build darwin && cgo

package fullvpn

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestMacDNSFixture(t *testing.T) {
	if os.Getenv("APM_DNS_FIXTURE") != "1" {
		return
	}
	release, err := ConfigureDNS()
	if err != nil {
		t.Fatal(err)
	}
	defer release()
	fmt.Println("ready")
	io.Copy(io.Discard, os.Stdin)
}

func macDNSPresent(t *testing.T) bool {
	t.Helper()
	cmd := exec.Command("/usr/sbin/scutil")
	cmd.Stdin = strings.NewReader("show State:/Network/Service/io.github.hecatoncheir.amneziaProxyManager/DNS\n")
	output, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	return strings.Contains(string(output), "172.31.255.2")
}

func TestMacDNSLifecycle(t *testing.T) {
	if os.Getenv("APM_VALIDATE_DNS") != "1" || os.Geteuid() != 0 {
		t.Skip("нужен явный запуск нативной DNS-проверки от администратора")
	}
	if macDNSPresent(t) {
		t.Skip("системный VPN уже использует собственный DNS")
	}
	for _, crash := range []bool{false, true} {
		t.Run(fmt.Sprint("crash=", crash), func(t *testing.T) { checkMacDNSLifecycle(t, crash) })
	}
}

func checkMacDNSLifecycle(t *testing.T, crash bool) {
	t.Helper()
	cmd := exec.Command(os.Args[0], "-test.run=^TestMacDNSFixture$")
	cmd.Env = append(os.Environ(), "APM_DNS_FIXTURE=1")
	input, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	output, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { cmd.Process.Kill() })
	checkMacDNSStarted(t, output)
	stopMacDNSFixture(cmd, input, crash)
	checkMacDNSRemoved(t)
}

func checkMacDNSStarted(t *testing.T, output io.Reader) {
	t.Helper()
	scanner := bufio.NewScanner(output)
	if !scanner.Scan() || scanner.Text() != "ready" {
		t.Fatal("не создан временный системный DNS")
	}
	if !macDNSPresent(t) {
		t.Fatal("DNS отсутствует в Dynamic Store")
	}
}

func stopMacDNSFixture(cmd *exec.Cmd, input io.Closer, crash bool) {
	if crash {
		cmd.Process.Kill()
	} else {
		input.Close()
	}
	cmd.Wait()
}

func checkMacDNSRemoved(t *testing.T) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if !macDNSPresent(t) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("после остановки/аварии остался временный DNS")
}
