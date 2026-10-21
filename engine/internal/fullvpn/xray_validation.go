package fullvpn

import (
	"encoding/json"
	"errors"
	"regexp"
	"strings"
)

// Повышенный worker принимает безопасный формат VLESS, даже если IPC обходит UI.
var forbiddenKey = regexp.MustCompile(`(?i)file|certificate|keylog|dialerproxy|sockopt|proxysettings|downloadsettings`)

var streamFields = map[string]string{
	"realitySettings":     "serverName fingerprint publicKey password shortId spiderX mldsa65Verify",
	"tlsSettings":         "serverName fingerprint alpn allowInsecure minVersion maxVersion pinnedPeerCertSha256 echConfigList",
	"sockopt":             "dialerProxy domainStrategy tcpFastOpen tcpNoDelay",
	"xhttpSettings":       "path host mode headers xmux extra",
	"splithttpSettings":   "path host mode headers xmux extra",
	"wsSettings":          "path host headers maxEarlyData earlyDataHeaderName acceptProxyProtocol",
	"grpcSettings":        "serviceName multiMode idle_timeout health_check_timeout permit_without_stream initial_windows_size",
	"httpupgradeSettings": "path host headers",
	"kcpSettings":         "mtu tti uplinkCapacity downlinkCapacity congestion readBufferSize writeBufferSize header seed",
	"tcpSettings":         "header", "rawSettings": "header",
}

func ValidateProfile(family, configuration string) error {
	if family != "xray" {
		return nil
	}
	var data map[string]any
	if json.Unmarshal([]byte(configuration), &data) != nil {
		return invalidProfile()
	}
	if err := allowedKeys(data, "log inbounds outbounds"); err != nil {
		return err
	}
	return validateOutbounds(data["outbounds"])
}

func invalidProfile() error { return errors.New("invalid_config") }

func allowedKeys(data map[string]any, fields string) error {
	allowed := " " + fields + " "
	for key := range data {
		if !strings.Contains(allowed, " "+key+" ") {
			return invalidProfile()
		}
	}
	return nil
}

func safeFields(value any, fields string) error {
	data, ok := value.(map[string]any)
	if !ok {
		return invalidProfile()
	}
	if err := allowedKeys(data, fields); err != nil {
		return err
	}
	for _, value := range data {
		if err := safeTree(value, 0); err != nil {
			return err
		}
	}
	return nil
}

func validateOutbounds(value any) error {
	outbounds, ok := value.([]any)
	if !ok || len(outbounds) == 0 {
		return invalidProfile()
	}
	for _, value := range outbounds {
		if err := validateOutbound(value); err != nil {
			return err
		}
	}
	return nil
}

func validateOutbound(value any) error {
	data, ok := value.(map[string]any)
	if !ok || data["protocol"] != "vless" {
		return invalidProfile()
	}
	if err := allowedKeys(data, "tag protocol settings streamSettings mux"); err != nil {
		return err
	}
	return validateOutboundSettings(data)
}

func validateOutboundSettings(data map[string]any) error {
	if err := validateVnext(data["settings"]); err != nil {
		return err
	}
	if err := validateStream(data["streamSettings"]); err != nil {
		return err
	}
	value, ok := data["mux"]
	if !ok {
		return nil
	}
	return safeFields(value, "enabled concurrency xudpConcurrency xudpProxyUDP443")
}

func validateVnext(value any) error {
	data, ok := value.(map[string]any)
	if !ok {
		return invalidProfile()
	}
	if err := allowedKeys(data, "vnext"); err != nil {
		return err
	}
	servers, ok := data["vnext"].([]any)
	if !ok || len(servers) != 1 {
		return invalidProfile()
	}
	return validateServer(servers[0])
}

func validateServer(value any) error {
	data, ok := value.(map[string]any)
	if !ok {
		return invalidProfile()
	}
	if err := allowedKeys(data, "address port users"); err != nil {
		return err
	}
	return validateUsers(data["users"])
}

func validateUsers(value any) error {
	users, ok := value.([]any)
	if !ok || len(users) == 0 {
		return invalidProfile()
	}
	for _, user := range users {
		if err := safeFields(user, "id encryption flow level"); err != nil {
			return err
		}
	}
	return nil
}

func validateStream(value any) error {
	data, ok := value.(map[string]any)
	if !ok {
		return invalidProfile()
	}
	for name, value := range data {
		if err := validateStreamField(name, value); err != nil {
			return err
		}
	}
	return nil
}

func validateStreamField(name string, value any) error {
	if name == "network" || name == "security" {
		return safeTree(value, 0)
	}
	fields, ok := streamFields[name]
	if !ok {
		return invalidProfile()
	}
	return safeTransport(value, fields)
}

func safeTransport(value any, fields string) error {
	if err := safeFields(value, fields); err != nil {
		return err
	}
	data := value.(map[string]any)
	if data["allowInsecure"] == true || data["acceptProxyProtocol"] == true {
		return invalidProfile()
	}
	return nil
}

func safeTree(value any, depth int) error {
	if depth > 8 {
		return invalidProfile()
	}
	switch typed := value.(type) {
	case map[string]any:
		return safeMap(typed, depth)
	case []any:
		return safeList(typed, depth)
	default:
		return nil
	}
}

func safeMap(data map[string]any, depth int) error {
	for key, value := range data {
		if forbiddenKey.MatchString(key) {
			return invalidProfile()
		}
		if err := safeTree(value, depth+1); err != nil {
			return err
		}
	}
	return nil
}

func safeList(data []any, depth int) error {
	for _, value := range data {
		if err := safeTree(value, depth+1); err != nil {
			return err
		}
	}
	return nil
}
