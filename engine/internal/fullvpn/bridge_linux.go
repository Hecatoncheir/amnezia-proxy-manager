package fullvpn

import (
	"errors"
	"golang.org/x/sys/unix"
	"net"
	"os/exec"
)

func authorizationCommand(executable, path string) (*exec.Cmd, error) {
	if Privileged() {
		return exec.Command(executable, "--ipc-pipe", path), nil
	}
	if _, err := systemBinary("/usr/bin/pkexec"); err != nil {
		return nil, errors.New("vpn_authorization_unavailable")
	}
	return exec.Command("/usr/bin/pkexec", executable, "--ipc-pipe", path), nil
}

func rootPeer(connection net.Conn) error {
	raw, err := connection.(*net.UnixConn).SyscallConn()
	if err != nil {
		return err
	}
	var credentials *unix.Ucred
	var credentialError error
	err = raw.Control(func(fd uintptr) {
		credentials, credentialError = unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED)
	})
	if err != nil {
		return err
	}
	if credentialError != nil {
		return credentialError
	}
	if credentials.Uid != 0 {
		return errors.New("vpn_pipe_untrusted")
	}
	return nil
}
