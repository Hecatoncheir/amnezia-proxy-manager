package fullvpn

import (
	"errors"
	"golang.org/x/sys/unix"
	"net"
	"os/exec"
	"strconv"
	"strings"
	"unicode"
)

func authorizationCommand(executable, path string) (*exec.Cmd, error) {
	if Privileged() {
		return exec.Command(executable, "--ipc-pipe", path), nil
	}
	script, err := authorizationScript(executable, path)
	if err != nil {
		return nil, err
	}
	return exec.Command("/usr/bin/osascript", "-e", script), nil
}

func authorizationScript(executable, path string) (string, error) {
	if strings.IndexFunc(executable+path, unicode.IsControl) >= 0 {
		return "", errors.New("vpn_elevation_failed")
	}
	command := shellArgument(executable) + " --ipc-pipe " + shellArgument(path)
	return "do shell script " + strconv.Quote(command) + " with administrator privileges", nil
}

func shellArgument(value string) string { return "'" + strings.ReplaceAll(value, "'", `'"'"'`) + "'" }

func rootPeer(connection net.Conn) error {
	raw, err := connection.(*net.UnixConn).SyscallConn()
	if err != nil {
		return err
	}
	var credentials *unix.Xucred
	var credentialError error
	err = raw.Control(func(fd uintptr) {
		credentials, credentialError = unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
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
