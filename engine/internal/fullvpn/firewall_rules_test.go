package fullvpn

import (
	"net/netip"
	"strings"
	"testing"
)

func firewallTestPlan() Plan {
	return Plan{Endpoints: []Endpoint{
		{Address: netip.MustParseAddr("192.0.2.10"), Port: 443, Protocol: "tcp"},
		{Address: netip.MustParseAddr("2001:db8::10"), Port: 51820, Protocol: "udp"},
	}}
}

func TestUnixRulesRestrictServerExceptions(t *testing.T) {
	plan := firewallTestPlan()
	nft, err := nftRules(plan, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, text := range []string{"policy drop", `oifname { "lo", "apm-vpn" }`, "ip daddr 192.0.2.10 tcp dport 443 accept", "ip6 daddr 2001:db8::10 udp dport 51820 accept", "counter drop"} {
		if !strings.Contains(nft, text) {
			t.Fatalf("nft: нет %q", text)
		}
	}
	pf, err := pfRules(plan)
	if err != nil {
		t.Fatal(err)
	}
	for _, text := range []string{"on lo0", "on utun233", "inet proto tcp to 192.0.2.10 port 443", "inet6 proto udp to 2001:db8::10 port 51820", `block drop out quick all label "amnezia-proxy-manager"`} {
		if !strings.Contains(pf, text) {
			t.Fatalf("PF: нет %q", text)
		}
	}
	if strings.Contains(nft, "ct state established") || strings.Contains(pf, "keep state") {
		t.Fatal("старые прямые соединения могут обойти блокировку")
	}
}

func TestNFTRetryIsAtomic(t *testing.T) {
	rules, err := nftRules(firewallTestPlan(), true)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(rules, "flush chain inet "+nftTable+" output\n") {
		t.Fatal("не обновляется существующая цепочка")
	}
	if strings.Contains(rules, "delete table") || strings.Contains(rules, "flush ruleset") {
		t.Fatal("снимается защита или затрагиваются чужие таблицы")
	}
}

func TestUnixRulesRejectInvalidEndpoints(t *testing.T) {
	for _, plan := range []Plan{{}, {Endpoints: []Endpoint{{Address: netip.MustParseAddr("192.0.2.1"), Port: 443, Protocol: "tcp; accept"}}}, {Endpoints: []Endpoint{{Address: netip.MustParseAddr("192.0.2.1"), Protocol: "udp"}}}} {
		if _, err := nftRules(plan, false); err == nil {
			t.Fatal("невалидное исключение nft принято")
		}
		if _, err := pfRules(plan); err == nil {
			t.Fatal("невалидное исключение PF принято")
		}
	}
}

func TestPinnedBinariesCoverAllTargets(t *testing.T) {
	for platform, binaries := range pinnedBinaries {
		for _, family := range []string{"awg", "xray", "tun"} {
			if len(binaries[family]) != 64 {
				t.Fatalf("нет SHA-256 %s/%s", platform, family)
			}
		}
	}
}

func TestEndpointsKeepProtocolAndPort(t *testing.T) {
	awg, err := Endpoints("awg", "Endpoint = [2001:db8::1]:51820")
	if err != nil || len(awg) != 1 {
		t.Fatalf("AWG: %v", err)
	}
	if awg[0].Protocol != "udp" || awg[0].Port != 51820 {
		t.Fatal(awg)
	}
	xray, err := Endpoints("xray", safeVLESS)
	if err != nil || len(xray) != 1 {
		t.Fatalf("VLESS: %v", err)
	}
	if xray[0].Protocol != "tcp" || xray[0].Port != 443 {
		t.Fatal(xray)
	}
}
