//go:build !windows

package autostart

import (
	"encoding/xml"
	"strings"
	"testing"
)

func TestRenderAutostart(t *testing.T) {
	binary := "/tmp/Пример с пробелами/quote\"$%app"
	linux := render(binary, "linux")
	if !strings.Contains(linux, "%%") || !strings.Contains(linux, "Exec=\"") || !strings.Contains(linux, " --autostart\n") {
		t.Fatal("не экранирована команда")
	}
	mac := render(binary, "darwin")
	decoder := xml.NewDecoder(strings.NewReader(mac))
	for {
		_, err := decoder.Token()
		if err != nil {
			if err.Error() != "EOF" {
				t.Fatal(err)
			}
			break
		}
	}
	if !strings.Contains(mac, "<key>RunAtLoad</key>") || !strings.Contains(mac, "<string>--autostart</string>") {
		t.Fatal("нет запуска при входе")
	}
}
