// Package validation проверяет конфигурацию без передачи ключей в аргументах.
package validation

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/upstream"
)

const MaxConfig = 65536

// Validate не возвращает stderr upstream: он может содержать ключи.
func Validate(binary, sum string, input io.Reader) (result error) {
	return validate(binary, sum, input, upstream.VerifyBinary, func(ctx context.Context, binary, path string) (*exec.Cmd, error) {
		return upstream.ConfigTestCommand(ctx, upstream.Config{Binary: binary, Profile: path})
	})
}

func ValidateXray(binary, sum string, input io.Reader) error {
	return validate(binary, sum, input, upstream.VerifyXrayBinary, func(ctx context.Context, binary, path string) (*exec.Cmd, error) {
		return upstream.XrayCommand(ctx, binary, path, true)
	})
}

func validate(binary, sum string, input io.Reader, verify func(string, string) error, commandFor func(context.Context, string, string) (*exec.Cmd, error)) (result error) {
	if err := verify(binary, sum); err != nil {
		return errors.New("движок не прошёл проверку")
	}
	data, err := io.ReadAll(io.LimitReader(input, MaxConfig+1))
	defer clear(data)
	if err != nil || len(data) == 0 || len(data) > MaxConfig {
		return errors.New("недопустимый размер конфигурации")
	}
	directory, err := privateDirectory()
	if err != nil {
		return errors.New("не удалось защитить временный каталог")
	}
	defer func() {
		if err := os.RemoveAll(directory); err != nil {
			result = errors.New("не удалось удалить временную конфигурацию")
		}
	}()
	path := filepath.Join(directory, "profile.conf")
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return errors.New("не удалось создать конфигурацию")
	}
	_, writeErr := file.Write(data)
	closeErr := file.Close()
	if writeErr != nil || closeErr != nil {
		return errors.New("не удалось записать конфигурацию")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	command, err := commandFor(ctx, binary, path)
	if err != nil {
		return errors.New("не удалось подготовить проверку")
	}
	command.Stdout, command.Stderr = io.Discard, io.Discard
	if err := command.Run(); err != nil {
		return errors.New("движок отклонил конфигурацию или не ответил")
	}
	return nil
}
