package validation

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"path/filepath"
	"unsafe"

	"golang.org/x/sys/windows"
)

func privateDirectory() (string, error) {
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return "", err
	}
	// Защищённая DACL с наследованием только текущему пользователю и SYSTEM.
	descriptor, err := windows.SecurityDescriptorFromString(
		"D:P(A;OICI;FA;;;" + user.User.Sid.String() + ")(A;OICI;FA;;;SY)")
	if err != nil {
		return "", err
	}
	var token [16]byte
	if _, err := rand.Read(token[:]); err != nil {
		return "", err
	}
	path := filepath.Join(os.TempDir(), "amnezia-config-"+hex.EncodeToString(token[:]))
	name, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return "", err
	}
	attributes := windows.SecurityAttributes{
		Length:             uint32(unsafe.Sizeof(windows.SecurityAttributes{})),
		SecurityDescriptor: descriptor,
	}
	if err := windows.CreateDirectory(name, &attributes); err != nil {
		return "", err
	}
	return path, nil
}
