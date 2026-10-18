package upstream

import (
	"context"
	"crypto/sha256"
	"debug/buildinfo"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const XrayVersion = "26.7.28"

var xrayHashes = map[string]string{
	"windows/amd64": "1d9674327972a21afd4c906a7a72bb0856935aa9e0227c87f34f03d11a88bddf",
	"linux/amd64":   "64d46afb80adea1bf97a0d467e83f4a9ac1ebd0995891e84bca3f1a1d1affb1d",
	"darwin/arm64":  "bd4154efa640c5b8e21f10b68afcc9177c4f1f543be3ec0485b10c499b2a4b27",
}

func VerifyXrayBinary(path, sum string) error {
	expected := xrayHashes[runtime.GOOS+"/"+runtime.GOARCH]
	if expected == "" || sum != expected {
		return errors.New("непроверенная сборка Xray")
	}
	file, err := os.Open(path)
	if err != nil {
		return errors.New("Xray недоступен")
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil || hex.EncodeToString(hash.Sum(nil)) != expected {
		return errors.New("SHA-256 Xray не совпадает")
	}
	info, err := buildinfo.Read(file)
	if err != nil || info.Path != "github.com/xtls/xray-core/main" {
		return errors.New("неверный формат Xray")
	}
	settings := map[string]string{}
	for _, s := range info.Settings {
		settings[s.Key] = s.Value
	}
	if settings["GOOS"] != runtime.GOOS || settings["GOARCH"] != runtime.GOARCH {
		return errors.New("неверная платформа Xray")
	}
	return nil
}

func XrayCommand(ctx context.Context, binary, config string, test bool) (*exec.Cmd, error) {
	if !filepath.IsAbs(binary) || !filepath.IsAbs(config) {
		return nil, errors.New("нужны абсолютные пути Xray")
	}
	args := []string{"run", "-config", config, "-format", "json"}
	if test {
		args = append(args, "-test")
	}
	cmd := exec.CommandContext(ctx, binary, args...)
	// Не наследовать пути конфигов/ресурсов и настройки логирования Xray.
	cmd.Env = []string{}
	for _, entry := range os.Environ() {
		if strings.HasPrefix(strings.ToUpper(entry), "XRAY_") {
			continue
		}
		cmd.Env = append(cmd.Env, entry)
	}
	return cmd, nil
}
