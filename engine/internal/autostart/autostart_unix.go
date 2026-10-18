//go:build !windows

package autostart

import (
	"bytes"
	"encoding/xml"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

func renderLegacy(binary, system string) string {
	if system == "darwin" {
		var escaped bytes.Buffer
		xml.EscapeText(&escaped, []byte(binary))
		return `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Label</key><string>io.github.hecatoncheir.amnezia-proxy-manager</string><key>ProgramArguments</key><array><string>` + escaped.String() + `</string></array><key>RunAtLoad</key><true/></dict></plist>`
	}
	escaped := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "`", "\\`", `$`, `\$`, `%`, `%%`).Replace(binary)
	command := strings.ReplaceAll(`"`+escaped+`"`, `\`, `\\`)
	return "[Desktop Entry]\nType=Application\nName=Amnezia Proxy\nExec=" + command + "\nTerminal=false\n"
}
func render(binary, system string) string {
	legacy := renderLegacy(binary, system)
	if system == "darwin" {
		return strings.Replace(legacy, "</array>", "<string>--autostart</string></array>", 1)
	}
	return strings.Replace(legacy, "\nTerminal=false", " --autostart\nTerminal=false", 1)
}
func apply(action, binary string) (bool, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return false, err
	}
	var path string
	switch runtime.GOOS {
	case "darwin":
		path = filepath.Join(home, "Library", "LaunchAgents", "io.github.hecatoncheir.amnezia-proxy-manager.plist")
	case "linux":
		root := os.Getenv("XDG_CONFIG_HOME")
		if !filepath.IsAbs(root) {
			root = filepath.Join(home, ".config")
		}
		path = filepath.Join(root, "autostart", "amnezia-proxy-manager.desktop")
	default:
		return false, errors.New("автозапуск недоступен")
	}
	expected := render(binary, runtime.GOOS)
	if action == "enable" {
		if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			return false, err
		}
		file, err := os.CreateTemp(filepath.Dir(path), ".amnezia-autostart-")
		if err != nil {
			return false, err
		}
		name := file.Name()
		defer os.Remove(name)
		_, writeErr := file.WriteString(expected)
		closeErr := file.Close()
		if writeErr != nil {
			return false, writeErr
		}
		if closeErr != nil {
			return false, closeErr
		}
		if err = os.Rename(name, path); err != nil {
			return false, err
		}
	}
	if action == "disable" {
		err = os.Remove(path)
		if err != nil && !os.IsNotExist(err) {
			return false, err
		}
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return string(data) == expected || string(data) == renderLegacy(binary, runtime.GOOS), nil
}
