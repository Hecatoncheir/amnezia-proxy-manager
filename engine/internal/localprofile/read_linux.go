package localprofile

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

const Supported = true

func ReadActive() ([]byte, error) {
	root := os.Getenv("XDG_CONFIG_HOME")
	if !filepath.IsAbs(root) {
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, err
		}
		root = filepath.Join(home, ".config")
	}
	raw, id, err := readQtSettings(filepath.Join(root, "AmneziaVPN.ORG", "AmneziaVPN.conf"))
	if err != nil {
		return nil, errors.New("не найдены доступные настройки AmneziaVPN текущего пользователя")
	}
	defer clear(raw)
	if strings.HasPrefix(string(raw), "EncData") {
		return nil, errors.New("эта версия AmneziaVPN шифрует настройки Linux; используйте экспорт профиля")
	}
	return selected(raw, id)
}
