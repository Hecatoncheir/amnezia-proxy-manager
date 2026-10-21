package fullvpn

import (
	"errors"
	"reflect"
	"testing"
)

func TestApplyNFTKeepsExistingProtection(t *testing.T) {
	var commands [][]string
	var applied string
	run := func(_ string, args []string, input string) (string, error) {
		commands = append(commands, args)
		if reflect.DeepEqual(args, []string{"list", "tables"}) {
			return "table inet " + nftTable + "\n", nil
		}
		applied = input
		return "", nil
	}
	if err := applyNFT(run, "nft", firewallTestPlan()); err != nil {
		t.Fatal(err)
	}
	if len(commands) != 2 || !reflect.DeepEqual(commands[1], []string{"-f", "-"}) {
		t.Fatal(commands)
	}
	expected, _ := nftRules(firewallTestPlan(), true)
	if applied != expected {
		t.Fatal("правила применены не одной транзакцией")
	}
}

func TestNftQueryFailureIsNotAnAbsentTable(t *testing.T) {
	calls := 0
	run := func(_ string, _ []string, _ string) (string, error) {
		calls++
		return "", errors.New("permission denied")
	}
	if err := applyNFT(run, "nft", firewallTestPlan()); err == nil {
		t.Fatal("ошибка ядра проигнорирована")
	}
	if calls != 1 {
		t.Fatal("после ошибки отправлены изменения")
	}
}
