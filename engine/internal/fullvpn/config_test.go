package fullvpn

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestPrepareAWG(t *testing.T) {
	for _, endpoint := range []string{"192.0.2.10:443", "[2001:db8::10]:443"} {
		plan, err := Prepare(context.Background(), "awg", "[Peer]\nEndpoint = "+endpoint+"\n")
		if err != nil || len(plan.Exclude) != 1 || !strings.Contains(plan.Configuration, endpoint) {
			t.Fatalf("%+v: %v", plan, err)
		}
	}
	for _, configuration := range []string{"[Peer]", "Endpoint = invalid"} {
		if _, err := Prepare(context.Background(), "awg", configuration); err == nil {
			t.Fatal("принят профиль без адреса сервера")
		}
	}
}

func TestPrepareXrayPreservesTLS(t *testing.T) {
	configuration := `{"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"127.0.0.1","port":443}]},"streamSettings":{"tlsSettings":{"serverName":"vpn.example"}}}]}`
	plan, err := Prepare(context.Background(), "xray", configuration)
	if err != nil || len(plan.Exclude) != 1 || !strings.Contains(plan.Configuration, "vpn.example") {
		t.Fatalf("%+v: %v", plan, err)
	}
	if _, err := Prepare(context.Background(), "xray", `{"outbounds":[]}`); err == nil {
		t.Fatal("нет сервера, но профиль принят")
	}
}

func TestConfigurationHasNoDirectOutbound(t *testing.T) {
	data, err := Configuration("127.0.0.1:19080", []string{"192.0.2.10/32"})
	if err != nil {
		t.Fatal(err)
	}
	var config map[string]any
	if err := json.Unmarshal(data, &config); err != nil {
		t.Fatal(err)
	}
	outbounds := config["outbounds"].([]any)
	if len(outbounds) != 1 || outbounds[0].(map[string]any)["type"] != "socks" {
		t.Fatal("есть обход VPN")
	}
	tun := config["inbounds"].([]any)[0].(map[string]any)
	if tun["auto_route"] != true || len(tun["address"].([]any)) != 2 {
		t.Fatal("нет маршрутов IPv4/IPv6")
	}
	dns := config["dns"].(map[string]any)["servers"].([]any)[0].(map[string]any)
	if dns["detour"] != "vpn" {
		t.Fatal("DNS обходит VPN")
	}
}

// Запускает настоящий CLI без изменения маршрутов; путь задаётся только для локальной проверки.
func TestRealTunConfiguration(t *testing.T) {
	binary := os.Getenv("APM_TEST_TUN_BINARY")
	if binary == "" {
		t.Skip("не указан проверяемый sing-box")
	}
	data, err := Configuration("127.0.0.1:19080", []string{"192.0.2.10/32"})
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "tun.json")
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(binary, "check", "-c", path).CombinedOutput()
	if err != nil {
		t.Fatalf("%v: %s", err, output)
	}
}
