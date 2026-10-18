package autostart

import (
	"golang.org/x/sys/windows/registry"
	"os"
	"path/filepath"
	"testing"
)

func TestWindowsRunKey(t *testing.T) {
	path := `Software\AmneziaProxyManager\TestAutostart`
	// Изолированный ключ: реальная автозагрузка пользователя не меняется.
	defer registry.DeleteKey(registry.CURRENT_USER, path)
	binary := filepath.Join(t.TempDir(), "Пример с пробелами.exe")
	os.WriteFile(binary, []byte("fixture"), 0600)
	for _, step := range []struct {
		action string
		want   bool
	}{{"status", false}, {"enable", true}, {"status", true}, {"disable", false}, {"disable", false}} {
		got, err := runKey(step.action, binary, path, valueName)
		if err != nil || got != step.want {
			t.Fatalf("%s: %v %v", step.action, got, err)
		}
	}
	if _, err := Apply("enable", "relative.exe"); err == nil {
		t.Fatal("принят относительный путь")
	}
}
