package autostart

import (
	"errors"
	"golang.org/x/sys/windows/registry"
	"unicode/utf16"
)

const runPath = `Software\Microsoft\Windows\CurrentVersion\Run`
const valueName = "AmneziaProxyManager"

func apply(action, binary string) (bool, error) { return runKey(action, binary, runPath, valueName) }
func runKey(action, binary, path, name string) (bool, error) {
	command := `"` + binary + `"`
	if len(utf16.Encode([]rune(command))) > 260 {
		return false, errors.New("слишком длинный путь автозапуска")
	}
	var key registry.Key
	var err error
	if action == "enable" {
		key, _, err = registry.CreateKey(registry.CURRENT_USER, path, registry.QUERY_VALUE|registry.SET_VALUE)
	} else {
		access := uint32(registry.QUERY_VALUE)
		if action == "disable" {
			access |= registry.SET_VALUE
		}
		key, err = registry.OpenKey(registry.CURRENT_USER, path, access)
		if err == registry.ErrNotExist {
			return false, nil
		}
	}
	if err != nil {
		return false, err
	}
	defer key.Close()
	if action == "enable" {
		if err = key.SetStringValue(name, command); err != nil {
			return false, err
		}
	}
	if action == "disable" {
		err = key.DeleteValue(name)
		if err != nil && err != registry.ErrNotExist {
			return false, err
		}
	}
	value, _, err := key.GetStringValue(name)
	if err == registry.ErrNotExist {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	enabled := value == command
	if enabled && path == runPath {
		approved, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run`, registry.QUERY_VALUE)
		if err == nil {
			defer approved.Close()
			data, _, _ := approved.GetBinaryValue(name)
			if len(data) > 0 && (data[0] == 3 || data[0] == 7) {
				enabled = false
			}
		}
	}
	return enabled, nil
}
