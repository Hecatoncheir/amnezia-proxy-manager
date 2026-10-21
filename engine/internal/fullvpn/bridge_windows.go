package fullvpn

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"net"
	"os"
	"strings"
	"time"
	"unsafe"

	"github.com/Microsoft/go-winio"
	"golang.org/x/sys/windows"
)

const pipePrefix = `\\.\pipe\amnezia-proxy-vpn-`

func Bridge(input io.Reader, output io.Writer) error {
	name, listener, err := newPipeListener()
	if err != nil {
		return err
	}
	defer listener.Close()
	if err := requestElevation(name); err != nil {
		return err
	}
	return forwardPipe(listener, input, output)
}

func newPipeListener() (string, net.Listener, error) {
	token := make([]byte, 24)
	if _, err := rand.Read(token); err != nil {
		return "", nil, err
	}
	name := pipePrefix + hex.EncodeToString(token)
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return "", nil, err
	}
	listener, err := winio.ListenPipe(name, &winio.PipeConfig{SecurityDescriptor: "D:P(A;;GA;;;" + user.User.Sid.String() + ")(A;;GA;;;BA)(A;;GA;;;SY)", InputBufferSize: 65536, OutputBufferSize: 65536})
	return name, listener, err
}

func requestElevation(name string) error {
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	if err := elevate(executable, name); err != nil {
		return errors.New("vpn_elevation_denied")
	}
	return nil
}

func forwardPipe(listener net.Listener, input io.Reader, output io.Writer) error {
	timer := time.AfterFunc(90*time.Second, func() { listener.Close() })
	defer timer.Stop()
	connection, err := listener.Accept()
	if err != nil {
		return errors.New("vpn_elevation_failed")
	}
	defer connection.Close()
	if err := elevatedPeer(connection); err != nil {
		return err
	}
	timer.Stop()
	go func() { io.Copy(connection, input); connection.Close() }()
	_, err = io.Copy(output, connection)
	return err
}

func elevate(executable, pipe string) error {
	verb, _ := windows.UTF16PtrFromString("runas")
	file, err := windows.UTF16PtrFromString(executable)
	if err != nil {
		return err
	}
	arguments, _ := windows.UTF16PtrFromString(`--ipc-pipe "` + pipe + `"`)
	// SW_HIDE: вспомогательный процесс не открывает консоль.
	return windows.ShellExecute(0, verb, file, arguments, nil, windows.SW_HIDE)
}

func elevatedPeer(connection io.ReadWriteCloser) error {
	pid, err := peerPID(connection)
	if err != nil {
		return err
	}
	process, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(process)
	return requireElevatedToken(process)
}

func peerPID(connection io.ReadWriteCloser) (uint32, error) {
	raw, ok := connection.(interface{ Fd() uintptr })
	if !ok {
		return 0, errors.New("vpn_pipe_failed")
	}
	var pid uint32
	proc := windows.NewLazySystemDLL("kernel32.dll").NewProc("GetNamedPipeClientProcessId")
	result, _, err := proc.Call(raw.Fd(), uintptr(unsafe.Pointer(&pid)))
	if result == 0 {
		return 0, err
	}
	return pid, nil
}

func requireElevatedToken(process windows.Handle) error {
	var token windows.Token
	if err := windows.OpenProcessToken(process, windows.TOKEN_QUERY, &token); err != nil {
		return err
	}
	defer token.Close()
	if !token.IsElevated() {
		return errors.New("vpn_pipe_untrusted")
	}
	return nil
}

func Pipe(name string) (io.ReadWriteCloser, error) {
	if !Privileged() || !strings.HasPrefix(name, pipePrefix) || len(name) != len(pipePrefix)+48 {
		return nil, errors.New("vpn_pipe_untrusted")
	}
	if _, err := hex.DecodeString(strings.TrimPrefix(name, pipePrefix)); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	return winio.DialPipeContext(ctx, name)
}
