package session

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
)

func TestKillSwitchDefault(t *testing.T) {
	disabled := false
	if !(Request{AllTraffic: true}).KillSwitchEnabled() {
		t.Fatal("защита должна быть включена по умолчанию")
	}
	if (Request{}).KillSwitchEnabled() {
		t.Fatal("прокси не должен блокировать системную сеть")
	}
	if (Request{AllTraffic: true, KillSwitch: &disabled}).KillSwitchEnabled() {
		t.Fatal("не учтено явное отключение")
	}
}

func TestPrivateCopyRejectsTampering(t *testing.T) {
	directory := t.TempDir()
	source := filepath.Join(directory, "source.exe")
	if err := os.WriteFile(source, []byte("known runtime"), 0600); err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256([]byte("known runtime"))
	expected := hex.EncodeToString(hash[:])
	if err := copyVerified(source, filepath.Join(directory, "valid.exe"), expected); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(source, []byte("replaced"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := copyVerified(source, filepath.Join(directory, "invalid.exe"), expected); err == nil {
		t.Fatal("подменённый движок принят")
	}
}

func TestElevatedWorkerRejectsProxyOnlyRequest(t *testing.T) {
	m := New(nil)
	m.vpnOnly = true
	if err := m.Start(Request{Family: "xray", Configuration: `{}`}); err == nil {
		t.Fatal("повышенные права доступны обычному запросу")
	}
}

func TestPreservingStopDoesNotClearProtection(t *testing.T) {
	m := New(nil)
	m.blocked = true
	if err := m.stop(true); err != nil {
		t.Fatal(err)
	}
	if !m.blocked {
		t.Fatal("повторное подключение сняло защиту")
	}
}
