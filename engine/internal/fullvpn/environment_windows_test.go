package fullvpn

import (
	"strings"
	"testing"
)

func TestPrivilegedEnvironmentDoesNotInheritConfig(t *testing.T) {
	t.Setenv("XRAY_LOCATION_CONFDIR", "C:/untrusted")
	t.Setenv("SING_BOX_CONFIG", "C:/untrusted.json")
	t.Setenv("WIREPROXY_ADMIN", "0.0.0.0:9999")
	environment, err := Environment(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range environment {
		if strings.Contains(value, "untrusted") || strings.HasPrefix(value, "WIREPROXY_") {
			t.Fatal("унаследованы сетевые настройки")
		}
	}
}
