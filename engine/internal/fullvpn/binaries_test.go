package fullvpn

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

// Обе границы доверия должны разрешать одинаковые бинарники целевой платформы.
func TestElevatedPinsMatchUI(t *testing.T) {
	files := map[string]string{"awg": "engine_release.dart", "xray": "xray_policy.dart", "tun": "tun_policy.dart"}
	platforms := map[string]string{"windows/amd64": "windows-x64", "linux/amd64": "linux-x64", "darwin/arm64": "macos-arm64"}
	for family, name := range files {
		data, err := os.ReadFile(filepath.Join("../../../apps/desktop/lib/features/engine", name))
		if err != nil {
			t.Fatal(err)
		}
		for native, ui := range platforms {
			pattern := `(?s)["']` + regexp.QuoteMeta(ui) + `["']\s*:\s*\{.*?["']binarySHA256["']\s*:\s*["']([0-9a-f]{64})["']`
			match := regexp.MustCompile(pattern).FindSubmatch(data)
			if len(match) != 2 {
				t.Fatalf("нет хеша UI %s/%s", ui, family)
			}
			if string(match[1]) != pinnedBinaries[native][family] {
				t.Fatalf("хеши root/UI расходятся: %s/%s", native, family)
			}
		}
	}
}
