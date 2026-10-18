package autostart

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

func Apply(action, binary string) (bool, error) {
	if action != "status" && action != "enable" && action != "disable" {
		return false, errors.New("неизвестное действие")
	}
	if !filepath.IsAbs(binary) || strings.ContainsAny(binary, "\r\n\x00") {
		return false, errors.New("некорректный путь приложения")
	}
	if action == "enable" {
		info, err := os.Stat(binary)
		if err != nil || !info.Mode().IsRegular() {
			return false, errors.New("приложение не найдено")
		}
	}
	return apply(action, binary)
}
