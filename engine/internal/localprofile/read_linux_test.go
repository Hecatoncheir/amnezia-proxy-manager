package localprofile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadLinuxSettings(t *testing.T) {
	root := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", root)
	directory := filepath.Join(root, "AmneziaVPN.ORG")
	if err := os.Mkdir(directory, 0700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "AmneziaVPN.conf")
	fixture := qtFixture(selectedFixture)
	if err := os.WriteFile(path, []byte(fixture), 0600); err != nil {
		t.Fatal(err)
	}
	profile, err := ReadActive()
	if err != nil || string(profile) != `{"outbounds":[]}` {
		t.Fatal("не прочитан профиль", err)
	}
	unchanged, err := os.ReadFile(path)
	if err != nil || string(unchanged) != fixture {
		t.Fatal("исходные настройки изменены")
	}
}
