package fullvpn

import (
	"fmt"
	"strings"
)

const nftTable = "amnezia_proxy_vpn"
const pfAnchor = "com.apple/000.amnezia-proxy-manager"
const pfLabel = "amnezia-proxy-manager"

func ProtectionError(err error) string {
	code := err.Error()
	if code == "vpn_firewall_unavailable" || code == "vpn_firewall_conflict" {
		return code
	}
	return "vpn_firewall_failed"
}

func validEndpoints(endpoints []Endpoint) error {
	if len(endpoints) == 0 {
		return invalidProfile()
	}
	for _, entry := range endpoints {
		if !validEndpoint(entry) {
			return invalidProfile()
		}
	}
	return nil
}

func validEndpoint(entry Endpoint) bool {
	return entry.Address.IsValid() && entry.Port != 0 && (entry.Protocol == "tcp" || entry.Protocol == "udp")
}

func nftRules(plan Plan, exists bool) (string, error) {
	if err := validEndpoints(plan.Endpoints); err != nil {
		return "", err
	}
	var rules strings.Builder
	rules.WriteString(nftHeader(exists))
	prefix := "add rule inet " + nftTable + " output "
	rules.WriteString(prefix + `oifname { "lo", "apm-vpn" } accept` + "\n")
	for _, entry := range plan.Endpoints {
		rules.WriteString(prefix + nftEndpoint(entry) + "\n")
	}
	rules.WriteString(prefix + "udp sport 68 udp dport 67 accept\n")
	rules.WriteString(prefix + "udp sport 546 udp dport 547 accept\n")
	rules.WriteString(prefix + "ip6 daddr { fe80::/10, ff02::/16 } icmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept\n")
	rules.WriteString(prefix + "counter drop\n")
	return rules.String(), nil
}

func nftHeader(exists bool) string {
	if exists {
		return "flush chain inet " + nftTable + " output\n"
	}
	return "add table inet " + nftTable + "\nadd chain inet " + nftTable + " output { type filter hook output priority -150; policy drop; }\n"
}

func nftEndpoint(entry Endpoint) string {
	family := "ip"
	if entry.Address.Is6() {
		family = "ip6"
	}
	return fmt.Sprintf("%s daddr %s %s dport %d accept", family, entry.Address, entry.Protocol, entry.Port)
}

func pfRules(plan Plan) (string, error) {
	if err := validEndpoints(plan.Endpoints); err != nil {
		return "", err
	}
	var rules strings.Builder
	rules.WriteString("pass out quick on lo0 all no state\npass out quick on utun233 all no state\n")
	for _, entry := range plan.Endpoints {
		rules.WriteString(pfEndpoint(entry) + "\n")
	}
	rules.WriteString("pass out quick inet proto udp from any port 68 to any port 67 no state\n")
	rules.WriteString("pass out quick inet6 proto udp from any port 546 to any port 547 no state\n")
	rules.WriteString("pass out quick inet6 proto icmp6 to { fe80::/10, ff02::/16 } icmp6-type { routersol, routeradv, neighbrsol, neighbradv } no state\n")
	rules.WriteString(`block drop out quick all label "` + pfLabel + `"` + "\n")
	return rules.String(), nil
}

func pfEndpoint(entry Endpoint) string {
	family := "inet"
	if entry.Address.Is6() {
		family = "inet6"
	}
	return fmt.Sprintf("pass out quick %s proto %s to %s port %d no state", family, entry.Protocol, entry.Address, entry.Port)
}
