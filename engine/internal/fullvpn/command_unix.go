//go:build linux || darwin

package fullvpn

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

type commandRunner func(string, []string, string) (string, error)

func runSystemCommand(path string, args []string, input string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, args...)
	cmd.Env, _ = Environment(stateRoot)
	cmd.Stdin = strings.NewReader(input)
	var output, diagnostics bytes.Buffer
	cmd.Stdout, cmd.Stderr = &output, &diagnostics
	err := cmd.Run()
	if err != nil {
		return output.String() + diagnostics.String(), err
	}
	if len(args) == 1 && args[0] == "-E" {
		return output.String() + diagnostics.String(), nil
	}
	return output.String(), err
}

func systemBinary(paths ...string) (string, error) {
	for _, path := range paths {
		info, err := os.Stat(path)
		if err != nil {
			continue
		}
		if trustedSystemBinary(info) {
			return path, nil
		}
	}
	return "", errors.New("vpn_firewall_unavailable")
}

func trustedSystemBinary(info os.FileInfo) bool {
	stat, ok := info.Sys().(*syscall.Stat_t)
	return ok && stat.Uid == 0 && info.Mode().IsRegular() && info.Mode().Perm()&0022 == 0
}
