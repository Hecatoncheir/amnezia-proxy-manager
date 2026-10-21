// Package fullvpn направляет системный трафик в отдельный SOCKS5-вход VPN.
package fullvpn

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/netip"
	"strconv"
	"strings"
)

const InterfaceName = "AmneziaProxyVPN"
const BinarySHA256 = "5c19bb3f8c12d4e85b3d47fe63123a7624b314b58dd7a8e32f51004f1c4d2faf"

type Plan struct {
	Configuration string
	Exclude       []string
	Endpoints     []Endpoint
}

// Prepare разрешает только адрес VPN-сервера до включения сетевой блокировки.
func Prepare(ctx context.Context, family, configuration string) (Plan, error) {
	plan, err := preparePlan(ctx, family, configuration)
	if err != nil {
		return plan, err
	}
	plan.Endpoints, err = Endpoints(family, plan.Configuration)
	return plan, err
}

func preparePlan(ctx context.Context, family, configuration string) (Plan, error) {
	if family == "awg" {
		return prepareAWG(ctx, configuration)
	}
	return prepareXray(ctx, configuration)
}

func resolve(ctx context.Context, host string) (string, error) {
	if ip, err := netip.ParseAddr(host); err == nil {
		return ip.String(), nil
	}
	addresses, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
	if err != nil || len(addresses) == 0 {
		return "", errors.New("vpn_endpoint_failed")
	}
	return addresses[0].Unmap().String(), nil
}

func prefix(address string) string {
	ip := netip.MustParseAddr(address)
	return netip.PrefixFrom(ip, ip.BitLen()).String()
}

func prepareAWG(ctx context.Context, configuration string) (Plan, error) {
	lines := strings.Split(configuration, "\n")
	var exclude []string
	for i, line := range lines {
		updated, address, err := resolveAWGLine(ctx, line)
		if err != nil {
			return Plan{}, err
		}
		lines[i] = updated
		if address != "" {
			exclude = append(exclude, prefix(address))
		}
	}
	return awgPlan(lines, exclude)
}

func resolveAWGLine(ctx context.Context, line string) (string, string, error) {
	key, value, ok := strings.Cut(line, "=")
	if !ok || strings.TrimSpace(key) != "Endpoint" {
		return line, "", nil
	}
	host, port, err := net.SplitHostPort(strings.TrimSpace(value))
	if err != nil {
		return "", "", errors.New("invalid_config")
	}
	address, err := resolve(ctx, host)
	if err != nil {
		return "", "", err
	}
	return "Endpoint = " + net.JoinHostPort(address, port), address, nil
}

func awgPlan(lines, exclude []string) (Plan, error) {
	if len(exclude) == 0 {
		return Plan{}, errors.New("invalid_config")
	}
	return Plan{Configuration: strings.Join(lines, "\n"), Exclude: exclude}, nil
}

func prepareXray(ctx context.Context, configuration string) (Plan, error) {
	var data map[string]any
	if json.Unmarshal([]byte(configuration), &data) != nil {
		return Plan{}, errors.New("invalid_config")
	}
	var exclude []string
	outbounds, _ := data["outbounds"].([]any)
	for _, value := range outbounds {
		outbound, _ := value.(map[string]any)
		addresses, err := resolveOutbound(ctx, outbound)
		if err != nil {
			return Plan{}, err
		}
		exclude = append(exclude, addresses...)
	}
	if len(exclude) == 0 {
		return Plan{}, errors.New("invalid_config")
	}
	encoded, err := json.Marshal(data)
	return Plan{Configuration: string(encoded), Exclude: exclude}, err
}

func resolveOutbound(ctx context.Context, outbound map[string]any) ([]string, error) {
	settings, _ := outbound["settings"].(map[string]any)
	var exclude []string
	servers, _ := settings["vnext"].([]any)
	other, _ := settings["servers"].([]any)
	for _, value := range append(servers, other...) {
		server, _ := value.(map[string]any)
		host, _ := server["address"].(string)
		address, err := resolve(ctx, host)
		if err != nil {
			return nil, err
		}
		preserveServerName(outbound, host)
		server["address"] = address
		exclude = append(exclude, prefix(address))
	}
	return exclude, nil
}

func preserveServerName(outbound map[string]any, host string) {
	stream, _ := outbound["streamSettings"].(map[string]any)
	for _, name := range []string{"tlsSettings", "realitySettings"} {
		settings, _ := stream[name].(map[string]any)
		setServerName(settings, host)
	}
}

func setServerName(settings map[string]any, host string) {
	if settings == nil {
		return
	}
	if settings["serverName"] == nil || settings["serverName"] == "" {
		settings["serverName"] = host
	}
}

func Configuration(socks string, exclude []string) ([]byte, error) {
	host, port, err := net.SplitHostPort(socks)
	if err != nil {
		return nil, err
	}
	number, err := strconv.Atoi(port)
	if err != nil {
		return nil, err
	}
	return json.Marshal(map[string]any{
		"log": map[string]any{"disabled": true},
		"dns": map[string]any{"servers": []any{map[string]any{"type": "tcp", "tag": "vpn-dns", "server": "1.1.1.1", "detour": "vpn"}}, "final": "vpn-dns"},
		"inbounds": []any{map[string]any{"type": "tun", "tag": "system", "interface_name": TunInterfaceName(),
			"address": []string{"172.31.255.1/30", "fdfe:dcba:9876::1/126"}, "mtu": 1400,
			"auto_route": true, "strict_route": true, "stack": "gvisor", "route_exclude_address": exclude}},
		"outbounds": []any{map[string]any{"type": "socks", "tag": "vpn", "server": host, "server_port": number, "version": "5"}},
		"route":     map[string]any{"rules": []any{map[string]any{"port": 53, "action": "hijack-dns"}}, "final": "vpn", "auto_detect_interface": true},
	})
}
