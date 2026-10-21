//go:build linux || darwin

package fullvpn

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const socketPrefix = "apm-vpn-"

func Bridge(input io.Reader, output io.Writer) error {
	directory, err := os.MkdirTemp("/tmp", socketPrefix)
	if err != nil {
		return err
	}
	defer os.RemoveAll(directory)
	path := filepath.Join(directory, "control.sock")
	listener, err := net.Listen("unix", path)
	if err != nil {
		return err
	}
	defer listener.Close()
	process, exited, err := startAuthorization(path)
	if err != nil {
		return err
	}
	defer process.Process.Kill()
	return authorizedPipe(listener, exited, input, output)
}

func startAuthorization(path string) (*exec.Cmd, <-chan error, error) {
	executable, err := os.Executable()
	if err != nil {
		return nil, nil, err
	}
	cmd, err := authorizationCommand(executable, path)
	if err != nil {
		return nil, nil, err
	}
	cmd.Stdout, cmd.Stderr = io.Discard, io.Discard
	if err := cmd.Start(); err != nil {
		return nil, nil, errors.New("vpn_elevation_failed")
	}
	exited := make(chan error, 1)
	go func() { exited <- cmd.Wait() }()
	return cmd, exited, nil
}

func authorizedPipe(listener net.Listener, exited <-chan error, input io.Reader, output io.Writer) error {
	connection, err := acceptAuthorized(listener, exited)
	if err != nil {
		return err
	}
	defer connection.Close()
	if err := rootPeer(connection); err != nil {
		return err
	}
	go func() { io.Copy(connection, input); connection.Close() }()
	_, err = io.Copy(output, connection)
	return err
}

func acceptAuthorized(listener net.Listener, exited <-chan error) (net.Conn, error) {
	type result struct {
		connection net.Conn
		err        error
	}
	accepted := make(chan result, 1)
	go func() { connection, err := listener.Accept(); accepted <- result{connection, err} }()
	timer := time.NewTimer(90 * time.Second)
	defer timer.Stop()
	select {
	case value := <-accepted:
		return value.connection, value.err
	case <-exited:
		return nil, errors.New("vpn_elevation_denied")
	case <-timer.C:
		return nil, errors.New("vpn_elevation_failed")
	}
}

func Pipe(path string) (io.ReadWriteCloser, error) {
	if !Privileged() || !validSocketPath(path) {
		return nil, errors.New("vpn_pipe_untrusted")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	return (&net.Dialer{}).DialContext(ctx, "unix", path)
}

func validSocketPath(path string) bool {
	if filepath.Clean(path) != path || filepath.Base(path) != "control.sock" {
		return false
	}
	parent := filepath.Dir(path)
	return filepath.Dir(parent) == "/tmp" && strings.HasPrefix(filepath.Base(parent), socketPrefix)
}
