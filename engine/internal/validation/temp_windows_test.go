package validation

import (
	"golang.org/x/sys/windows"
	"strings"
	"testing"
)

func checkPermissions(t *testing.T, directory, file string) {
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{directory, file} {
		sd, err := windows.GetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, windows.DACL_SECURITY_INFORMATION)
		if err != nil {
			t.Fatal(err)
		}
		sddl := sd.String()
		if !strings.Contains(sddl, user.User.Sid.String()) || !strings.Contains(sddl, ";;;SY)") {
			t.Fatal("отсутствуют разрешения владельца или SYSTEM")
		}
		for _, sid := range []string{";;;WD)", ";;;BU)", ";;;AU)"} {
			if strings.Contains(sddl, sid) {
				t.Fatal("у других пользователей есть доступ к конфигурации")
			}
		}
	}
}
