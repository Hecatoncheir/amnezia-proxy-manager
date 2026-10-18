package autostart

import (
	"golang.org/x/sys/windows/registry"
	"os"
	"path/filepath"
	"strings"
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
	key, _, err := registry.CreateKey(registry.CURRENT_USER, path, registry.ALL_ACCESS)
	if err != nil {
		t.Fatal(err)
	}
	defer key.Close()
	if err := key.SetStringValue(valueName, `"`+binary+`"`); err != nil {
		t.Fatal(err)
	}
	if enabled, err := runKey("status", binary, path, valueName); err != nil || !enabled {
		t.Fatal("не распознана старая запись", err)
	}
	if _, err := runKey("enable", binary, path, valueName); err != nil {
		t.Fatal(err)
	}
	command, _, err := key.GetStringValue(valueName)
	if err != nil || !strings.HasSuffix(command, " --autostart") {
		t.Fatal("нет признака автозапуска", err)
	}
}
