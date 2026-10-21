//go:build linux

package fullvpn

import (
	"context"
	"encoding/json"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// Проверка ядра выполняется исключительно в новом network namespace.
func TestLinuxNftIntegration(t *testing.T) {
	if os.Getenv("APM_RUN_NETWORK_TESTS") != "1" {
		t.Skip("явная проверка nft в изолированном network namespace")
	}
	if os.Geteuid() != 0 {
		t.Fatal("для создания network namespace нужны права root")
	}
	if os.Getenv("APM_FIREWALL_CHILD") != "1" {
		runIsolatedFirewallTest(t)
		return
	}
	current, err := os.Readlink("/proc/self/ns/net")
	if err != nil || current == os.Getenv("APM_PARENT_NETNS") {
		t.Fatal("изоляция сети не подтверждена")
	}
	runLinuxFirewallScenario(t)
}

func runIsolatedFirewallTest(t *testing.T) {
	t.Helper()
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	namespace, err := os.Readlink("/proc/self/ns/net")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "/usr/bin/unshare", "--net", executable, "-test.run=^TestLinuxNftIntegration$", "-test.v")
	cmd.Env = append(os.Environ(), "APM_FIREWALL_CHILD=1", "APM_PARENT_NETNS="+namespace)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("изолированная проверка: %v\n%s", err, output)
	}
	t.Log(string(output))
}

func runLinuxFirewallScenario(t *testing.T) {
	configureTestInterfaces(t)
	plan := Plan{Endpoints: []Endpoint{
		{Address: netip.MustParseAddr("198.18.0.2"), Port: 51820, Protocol: "udp"},
		{Address: netip.MustParseAddr("fd18::2"), Port: 51820, Protocol: "udp"},
	}}
	if err := Protect("", plan); err != nil {
		t.Fatal(err)
	}
	defer Release()
	if !IsProtected() {
		t.Fatal("правила не установлены")
	}
	assertLoopbackAvailable(t)
	assertBlockedDatagram(t, "198.18.0.2:4000")
	assertBlockedDatagram(t, "[fd18::2]:4000")
	assertAllowedDatagram(t, "198.18.0.2:51820")
	assertAllowedDatagram(t, "[fd18::2]:51820")
	assertAllowedDatagram(t, "198.19.0.2:4000")
	assertAllowedDatagram(t, "[fd19::2]:4000")
	assertFirewallRetry(t, plan)
	if err := Release(); err != nil {
		t.Fatal(err)
	}
	if IsProtected() {
		t.Fatal("правила не удалены")
	}
}

func configureTestInterfaces(t *testing.T) {
	t.Helper()
	path, err := systemBinary("/usr/sbin/ip", "/sbin/ip")
	if err != nil {
		t.Fatal(err)
	}
	commands := []string{
		"link set lo up",
		"link add apm-physical type dummy", "addr add 198.18.0.1/24 dev apm-physical", "-6 addr add fd18::1/64 dev apm-physical nodad", "link set apm-physical up",
		"link add apm-vpn type dummy", "addr add 198.19.0.1/24 dev apm-vpn", "-6 addr add fd19::1/64 dev apm-vpn nodad", "link set apm-vpn up",
	}
	for _, command := range commands {
		if output, err := runSystemCommand(path, strings.Fields(command), ""); err != nil {
			t.Fatalf("ip %s: %v %s", command, err, output)
		}
	}
}

func assertLoopbackAvailable(t *testing.T) {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	connection, err := net.DialTimeout("tcp4", listener.Addr().String(), time.Second)
	if err != nil {
		t.Fatal("локальный прокси заблокирован: ", err)
	}
	connection.Close()
}

func sendDatagram(t *testing.T, address string) {
	t.Helper()
	connection, err := net.DialTimeout("udp", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	connection.Write([]byte("network namespace probe"))
}

func droppedPackets(t *testing.T) uint64 {
	t.Helper()
	path, err := nftBinary()
	if err != nil {
		t.Fatal(err)
	}
	output, err := runSystemCommand(path, []string{"-j", "list", "chain", "inet", nftTable, "output"}, "")
	if err != nil {
		t.Fatal(err)
	}
	var data struct {
		NFTables []struct {
			Rule struct {
				Expr []struct{ Counter struct{ Packets uint64 } }
			}
		}
	}
	if err := json.Unmarshal([]byte(output), &data); err != nil {
		t.Fatal(err)
	}
	var packets uint64
	for _, entry := range data.NFTables {
		for _, expr := range entry.Rule.Expr {
			packets += expr.Counter.Packets
		}
	}
	return packets
}

func assertBlockedDatagram(t *testing.T, address string) {
	t.Helper()
	before := droppedPackets(t)
	sendDatagram(t, address)
	if droppedPackets(t) <= before {
		t.Fatalf("прямой пакет %s не заблокирован", address)
	}
}

func assertAllowedDatagram(t *testing.T, address string) {
	t.Helper()
	before := droppedPackets(t)
	sendDatagram(t, address)
	if droppedPackets(t) != before {
		t.Fatalf("разрешённый пакет %s заблокирован", address)
	}
}

func assertFirewallRetry(t *testing.T, plan Plan) {
	t.Helper()
	for i := range plan.Endpoints {
		plan.Endpoints[i].Port = 51821
	}
	if err := Protect("", plan); err != nil {
		t.Fatal(err)
	}
	assertBlockedDatagram(t, "198.18.0.2:51820")
	assertAllowedDatagram(t, "198.18.0.2:51821")
}
