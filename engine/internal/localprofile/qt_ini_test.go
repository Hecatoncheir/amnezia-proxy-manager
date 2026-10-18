package localprofile

import (
	"encoding/json"
	"strings"
	"testing"
)

const selectedFixture = `[{"storageServerId":"chosen","defaultContainer":"amnezia-xray","auth_data":{"token":"SECRET-TOKEN"},"containers":[{"container":"amnezia-xray","xray":{"last_config":"{\"outbounds\":[]}"}}]}]`

func qtFixture(value string) string {
	escaped := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`).Replace(value)
	return "[Conf]\nprivate=SECRET-SUBSCRIPTION\n[Servers]\ndefaultServerId=chosen\nserversList=@ByteArray(" + escaped + ")\n"
}

func TestQtIniSelection(t *testing.T) {
	raw, id, err := parseQtSettings(qtFixture(selectedFixture))
	if err != nil {
		t.Fatal(err)
	}
	profile, err := selected(raw, id)
	if err != nil || !json.Valid(profile) {
		t.Fatal("профиль не прочитан", err)
	}
	if strings.Contains(string(profile), "SECRET") {
		t.Fatal("лишние данные перенесены")
	}
	if string(profile) != `{"outbounds":[]}` {
		t.Fatal("перенесён неверный профиль")
	}
}

func TestQtEscapes(t *testing.T) {
	decoded, err := decodeQtValue(`"@ByteArray(\x45ncData\0\n\r\t\\\")"`)
	if err != nil || string(decoded) != "EncData\x00\n\r\t\\\"" {
		t.Fatalf("Qt escape: %q %v", decoded, err)
	}
	for _, value := range []string{`\`, `\q`, `\x`} {
		if _, err := decodeQtValue(value); err == nil {
			t.Fatal("принята повреждённая строка")
		}
	}
}

func TestQtNoSelectedProfile(t *testing.T) {
	raw, id, err := parseQtSettings("[Servers]\nserversList=@ByteArray([])\n")
	if err == nil || raw != nil || id != "" {
		t.Fatal("нет ошибки без выбранного профиля")
	}
	if _, err := selected([]byte(selectedFixture), "other"); err == nil {
		t.Fatal("выбран чужой профиль")
	}
}
