package session

import (
	"bufio"
	"context"
	"fmt"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/validation"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func TestGuardFixture(t *testing.T) {
	if os.Getenv("SESSION_GUARD_FIXTURE") != "1" {
		return
	}
	if GuardSupervisor() != nil {
		os.Exit(20)
	}
	path := os.Args[len(os.Args)-1]
	release, err := ownDirectory(filepath.Dir(path))
	if err != nil {
		os.Exit(21)
	}
	defer release()
	cmd := exec.CommandContext(context.Background(), os.Args[0], "-test.run=^TestEngineFixture$", "--", path)
	cmd.Env = append(os.Environ(), "SESSION_FIXTURE=1")
	kill, err := startProcess(cmd)
	if err != nil {
		os.Exit(22)
	}
	defer kill()
	fmt.Fprintln(os.Stdout, "ready")
	io.Copy(io.Discard, os.Stdin)
	kill()
	cmd.Wait()
	release()
	os.RemoveAll(filepath.Dir(path))
	os.Exit(0)
}
func TestEOFAndSupervisorDeath(t *testing.T) {
	if runtime.GOOS != "windows" && runtime.GOOS != "linux" && runtime.GOOS != "darwin" {
		t.Skip("авария supervisor требует отдельной проверки этой ОС")
	}
	for _, crash := range []bool{false, true} {
		socks, http := freeAddress(t), freeAddress(t)
		directory, err := validation.PrivateDirectory()
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { os.RemoveAll(directory) })
		config, err := configuration(Request{Family: "xray", Configuration: `{}`}, socks, http)
		if err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(directory, "profile.conf")
		os.WriteFile(path, config, 0600)
		cmd := exec.Command(os.Args[0], "-test.run=^TestGuardFixture$", "--", path)
		cmd.Env = append(os.Environ(), "SESSION_GUARD_FIXTURE=1")
		stdin, _ := cmd.StdinPipe()
		stdout, _ := cmd.StdoutPipe()
		if cmd.Start() != nil {
			t.Fatal("нет процесса")
		}
		t.Cleanup(func() { cmd.Process.Kill() })
		scanner := bufio.NewScanner(stdout)
		if !scanner.Scan() || scanner.Text() != "ready" {
			t.Fatal("нет защиты процесса")
		}
		deadline := time.Now().Add(5 * time.Second)
		for !listenerReady(socks, true) && time.Now().Before(deadline) {
			time.Sleep(20 * time.Millisecond)
		}
		if !listenerReady(socks, true) {
			t.Fatal("fixture не запущен")
		}
		cleanupOrphans()
		if _, err := os.Stat(path); err != nil {
			t.Fatal("удалён конфиг активного владельца")
		}
		if crash {
			cmd.Process.Kill()
		} else {
			stdin.Close()
		}
		cmd.Wait()
		deadline = time.Now().Add(3 * time.Second)
		for listenerReady(socks, true) && time.Now().Before(deadline) {
			time.Sleep(20 * time.Millisecond)
		}
		for _, address := range []string{socks, http} {
			l, err := net.Listen("tcp", address)
			if err != nil {
				t.Fatal("дерево пережило supervisor")
			}
			l.Close()
		}
		if crash {
			if _, err := os.Stat(path); err != nil {
				t.Fatal("нет аварийного файла для проверки")
			}
			cleanupOrphans()
		}
		if _, err := os.Stat(directory); !os.IsNotExist(err) {
			t.Fatal("остался временный конфиг")
		}
	}
}
