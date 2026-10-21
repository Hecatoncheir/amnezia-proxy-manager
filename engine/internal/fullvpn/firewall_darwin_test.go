package fullvpn

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestPFLayoutRejectsEarlierBypasses(t *testing.T) {
	if err := compatiblePFRoot("scrub-anchor \"com.apple/*\" all\nanchor \"com.apple/*\" all\n"); err != nil {
		t.Fatal(err)
	}
	for _, rules := range []string{"", "pass out quick all\nanchor \"com.apple/*\" all\n"} {
		if err := compatiblePFRoot(rules); err == nil {
			t.Fatal("обход PF принят")
		}
	}
	if err := compatiblePFAnchors("000.amnezia-proxy-manager\n200.AirDrop\n"); err != nil {
		t.Fatal(err)
	}
	if err := compatiblePFAnchors("000.aaaa\n"); err == nil {
		t.Fatal("ранний сторонний anchor принят")
	}
}

func TestMacAuthorizationQuoting(t *testing.T) {
	script, err := authorizationScript("/Applications/Мой ' VPN.app/Contents/MacOS/proxy-engine", "/tmp/apm-vpn-test/control.sock")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(script, "with administrator privileges") {
		t.Fatal(script)
	}
	if _, err := authorizationScript("/tmp/invalid\npath", "/tmp/apm-vpn-test/control.sock"); err == nil {
		t.Fatal("управляющие символы приняты")
	}
}

func TestPFNativeSyntax(t *testing.T) {
	if os.Getenv("APM_VALIDATE_PF") != "1" {
		t.Skip("нужен явный запуск проверки системного парсера PF")
	}
	rules, err := pfRules(firewallTestPlan())
	if err != nil {
		t.Fatal(err)
	}
	// -n только разбирает синтаксис: правила, состояния и режим PF не меняются.
	cmd := exec.Command("/usr/bin/sudo", "-n", pfctl, "-a", pfAnchor, "-nf", "-")
	cmd.Stdin = strings.NewReader(rules)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("PF: %v: %s", err, output)
	}
}
