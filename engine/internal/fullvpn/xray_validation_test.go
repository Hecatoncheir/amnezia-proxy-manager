package fullvpn

import (
	"strings"
	"testing"
)

const safeVLESS = `{"outbounds":[{"tag":"vpn","protocol":"vless","settings":{"vnext":[{"address":"192.0.2.10","port":443,"users":[{"id":"example","encryption":"none"}]}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"serverName":"vpn.example","alpn":["h2"]}}}]}`

func TestElevatedVLESSSchema(t *testing.T) {
	if err := ValidateProfile("xray", safeVLESS); err != nil {
		t.Fatal(err)
	}
	cases := []string{
		strings.Replace(safeVLESS, `"vless"`, `"freedom"`, 1),
		strings.Replace(safeVLESS, `"outbounds":`, `"dns":{"hosts":{}},"outbounds":`, 1),
		strings.Replace(safeVLESS, `"alpn":["h2"]`, `"certificateFile":"C:/private.pem"`, 1),
		strings.Replace(safeVLESS, `"alpn":["h2"]`, `"allowInsecure":true`, 1),
		strings.Replace(safeVLESS, `"tlsSettings":`, `"unknownSettings":`, 1),
		strings.Replace(safeVLESS, `"tlsSettings":{"serverName":"vpn.example","alpn":["h2"]}`, `"xhttpSettings":{"extra":{"downloadSettings":{"address":"192.0.2.20"}}}`, 1),
		strings.Replace(safeVLESS, `"tlsSettings":{"serverName":"vpn.example","alpn":["h2"]}`, `"xhttpSettings":{"extra":{"sockopt":{"dialerProxy":"direct"}}}`, 1),
	}
	for i, config := range cases {
		if err := ValidateProfile("xray", config); err == nil {
			t.Fatalf("небезопасный профиль %d принят", i)
		}
	}
}
