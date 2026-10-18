package session

import (
	"os"
	"path/filepath"
	"strings"
)

const markerText = "amnezia-manager-session-v1"

func ownDirectory(directory string) (func(), error) {
	file, err := os.OpenFile(filepath.Join(directory, "owner.lock"), os.O_CREATE|os.O_EXCL|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err = lockFile(file); err != nil {
		file.Close()
		return nil, err
	}
	if _, err = file.WriteString(markerText); err != nil {
		file.Close()
		return nil, err
	}
	return func() { file.Close() }, nil
}

// Удаляются только наши помеченные каталоги, владельца которых уже нет.
func cleanupOrphans() {
	root, err := filepath.Abs(os.TempDir())
	if err != nil {
		return
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), "amnezia-config-") || !entry.IsDir() || entry.Type()&os.ModeSymlink != 0 {
			continue
		}
		directory := filepath.Join(root, entry.Name())
		marker := filepath.Join(directory, "owner.lock")
		info, err := os.Lstat(marker)
		if err != nil || !info.Mode().IsRegular() || info.Size() != int64(len(markerText)) {
			continue
		}
		file, err := os.OpenFile(marker, os.O_RDWR, 0)
		if err != nil {
			continue
		}
		if lockFile(file) != nil {
			file.Close()
			continue
		}
		data := make([]byte, len(markerText))
		_, err = file.ReadAt(data, 0)
		if err == nil && string(data) == markerText {
			os.Remove(filepath.Join(directory, "profile.conf"))
		}
		file.Close()
		if err == nil && string(data) == markerText {
			os.Remove(marker)
			os.Remove(directory)
		}
	}
}
