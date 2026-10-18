package upstream

import (
	"crypto/sha256"
	"debug/buildinfo"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"runtime"
	"strings"
)

// VerifyBinary проверяет отдельный backend до запуска; Go на машине пользователя не нужен.
func VerifyBinary(path, expectedSHA256 string) error {
	expected, err := hex.DecodeString(expectedSHA256)
	if err != nil || len(expected) != sha256.Size {
		return errors.New("некорректная контрольная сумма backend")
	}
	file, err := os.Open(path)
	if err != nil {
		return errors.New("backend недоступен")
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil || !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), expectedSHA256) {
		return errors.New("контрольная сумма backend не совпадает")
	}
	info, err := buildinfo.Read(file)
	if err != nil || info.Path != "amnezia-proxy" {
		return errors.New("неизвестный формат backend")
	}
	settings := make(map[string]string)
	for _, setting := range info.Settings {
		settings[setting.Key] = setting.Value
	}
	if settings["vcs.revision"] != Revision || settings["vcs.modified"] != "false" {
		return errors.New("ревизия backend не поддерживается")
	}
	if settings["GOOS"] != runtime.GOOS || settings["GOARCH"] != runtime.GOARCH {
		return errors.New("платформа backend не совпадает")
	}
	return nil
}
