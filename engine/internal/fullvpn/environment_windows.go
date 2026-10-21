package fullvpn

import (
	"golang.org/x/sys/windows"
	"path/filepath"
)

// Исключаем пользовательские параметры, подмешивающие конфигурацию в повышенный процесс.
func Environment(directory string) ([]string, error) {
	root, err := windows.GetWindowsDirectory()
	if err != nil {
		return nil, err
	}
	return []string{
		"SystemRoot=" + root, "WINDIR=" + root,
		"PATH=" + filepath.Join(root, "System32") + ";" + root,
		"TEMP=" + directory, "TMP=" + directory,
		"USERPROFILE=" + directory, "APPDATA=" + directory, "LOCALAPPDATA=" + directory,
	}, nil
}
