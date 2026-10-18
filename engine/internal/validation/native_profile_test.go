package validation

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/localprofile"
	"net"
	"os"
	"strconv"
	"testing"
	"time"
)

// Опциональная диагностика структуры без адресов, идентификаторов и ключей.
func TestNativeProfileStructure(t *testing.T) {
	if os.Getenv("INSPECT_NATIVE_PROFILE") != "1" {
		t.Skip("требуется явное разрешение локальной диагностики")
	}
	data, err := localprofile.ReadActive()
	if err != nil {
		t.Fatal("профиль недоступен")
	}
	defer clear(data)
	var config map[string]any
	if json.Unmarshal(data, &config) != nil {
		t.Fatal("неверный JSON")
	}
	names := []string{}
	for key := range config {
		names = append(names, key)
	}
	t.Log("topFields", names)
	outbounds, _ := config["outbounds"].([]any)
	tags := map[string]int{}
	for i, value := range outbounds {
		out := value.(map[string]any)
		tag, _ := out["tag"].(string)
		tags[tag] = i
		fields := []string{}
		for k := range out {
			fields = append(fields, k)
		}
		t.Log("outbound", i, "fields", fields)
		if settings, ok := out["settings"].(map[string]any); ok {
			if servers, ok := settings["vnext"].([]any); ok && len(servers) > 0 {
				server := servers[0].(map[string]any)
				host, _ := server["address"].(string)
				port, _ := server["port"].(float64)
				connection, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(int(port))), 5*time.Second)
				if err == nil {
					connection.Close()
				}
				t.Log("outbound", i, "tcpReachable", err == nil)
			}
		}
	}
	if routing, ok := config["routing"].(map[string]any); ok {
		if rules, ok := routing["rules"].([]any); ok {
			for i, value := range rules {
				rule := value.(map[string]any)
				tag, _ := rule["outboundTag"].(string)
				fields := []string{}
				for k := range rule {
					fields = append(fields, k)
				}
				t.Log("rule", i, "fields", fields, "outboundIndex", tags[tag])
			}
		}
	}
}

// Явная сетевая проверка, без записи исходного профиля и вывода секретов.
func TestNativeXrayConnection(t *testing.T) {
	binary := os.Getenv("XRAY_NATIVE_PROBE")
	if binary == "" {
		t.Skip("явная локальная проверка не запрошена")
	}
	data, err := localprofile.ReadActive()
	if err != nil {
		t.Fatal("профиль недоступен")
	}
	defer clear(data)
	var config map[string]any
	if json.Unmarshal(data, &config) != nil {
		t.Fatal("неверный JSON")
	}
	config["inbounds"] = []any{map[string]any{"listen": "127.0.0.1", "protocol": "socks", "settings": map[string]any{"auth": "noauth", "udp": false}}, map[string]any{"listen": "127.0.0.1", "protocol": "http", "settings": map[string]any{}}}
	delete(config, "routing")
	delete(config, "dns")
	encoded, _ := json.Marshal(config)
	defer clear(encoded)
	binaryData, err := os.ReadFile(binary)
	if err != nil {
		t.Fatal("нет бинарника")
	}
	sum := fmt.Sprintf("%x", sha256.Sum256(binaryData))
	var probeError error
	if expected := os.Getenv("XRAY_SOURCE_SHA256"); expected != "" {
		if sum != expected {
			t.Fatal("хеш исходной сборки не совпадает")
		}
		probeError = probeXray(binary, bytes.NewReader(encoded))
	} else {
		probeError = ProbeXray(binary, sum, bytes.NewReader(encoded))
	}
	if probeError != nil {
		t.Fatal(probeError)
	}
}
