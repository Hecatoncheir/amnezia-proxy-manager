package fullvpn

import (
	"encoding/json"
	"net"
	"net/netip"
	"strconv"
	"strings"
)

// Исключение Unix-фильтра ограничено адресом, транспортом и портом VPN-сервера.
type Endpoint struct {
	Address  netip.Addr
	Port     uint16
	Protocol string
}

func Endpoints(family, configuration string) ([]Endpoint, error) {
	if family == "awg" {
		return awgEndpoints(configuration)
	}
	return xrayEndpoints(configuration)
}

func endpoint(host, port, protocol string) (Endpoint, error) {
	address, err := netip.ParseAddr(host)
	if err != nil {
		return Endpoint{}, invalidProfile()
	}
	number, err := strconv.ParseUint(port, 10, 16)
	if err != nil || number == 0 {
		return Endpoint{}, invalidProfile()
	}
	return Endpoint{Address: address.Unmap(), Port: uint16(number), Protocol: protocol}, nil
}

func awgEndpoints(configuration string) ([]Endpoint, error) {
	var result []Endpoint
	for _, line := range strings.Split(configuration, "\n") {
		key, value, _ := strings.Cut(line, "=")
		if strings.TrimSpace(key) != "Endpoint" {
			continue
		}
		entry, err := awgEndpoint(strings.TrimSpace(value))
		if err != nil {
			return nil, err
		}
		result = append(result, entry)
	}
	return requireEndpoints(result)
}

func awgEndpoint(value string) (Endpoint, error) {
	host, port, err := net.SplitHostPort(value)
	if err != nil {
		return Endpoint{}, invalidProfile()
	}
	return endpoint(host, port, "udp")
}

func requireEndpoints(result []Endpoint) ([]Endpoint, error) {
	if len(result) == 0 {
		return nil, invalidProfile()
	}
	return result, nil
}

func xrayEndpoints(configuration string) ([]Endpoint, error) {
	var data map[string]any
	if json.Unmarshal([]byte(configuration), &data) != nil {
		return nil, invalidProfile()
	}
	outbounds, _ := data["outbounds"].([]any)
	var result []Endpoint
	for _, value := range outbounds {
		entries, err := outboundEndpoints(value)
		if err != nil {
			return nil, err
		}
		result = append(result, entries...)
	}
	return requireEndpoints(result)
}

func outboundEndpoints(value any) ([]Endpoint, error) {
	data, _ := value.(map[string]any)
	settings, _ := data["settings"].(map[string]any)
	servers, _ := settings["vnext"].([]any)
	protocol := outboundProtocol(data)
	var result []Endpoint
	for _, server := range servers {
		entry, err := serverEndpoint(server, protocol)
		if err != nil {
			return nil, err
		}
		result = append(result, entry)
	}
	return result, nil
}

func outboundProtocol(data map[string]any) string {
	stream, _ := data["streamSettings"].(map[string]any)
	if stream["network"] == "kcp" {
		return "udp"
	}
	return "tcp"
}

func serverEndpoint(value any, protocol string) (Endpoint, error) {
	server, _ := value.(map[string]any)
	host, _ := server["address"].(string)
	port, _ := server["port"].(float64)
	if port != float64(uint16(port)) {
		return Endpoint{}, invalidProfile()
	}
	return endpoint(host, strconv.Itoa(int(port)), protocol)
}
