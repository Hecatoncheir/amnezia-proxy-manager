//go:build !windows && !darwin

package session

import (
	"os/exec"
	"runtime"
	"sync"
	"syscall"
)

func GuardSupervisor() error { return nil }
func startProcess(cmd *exec.Cmd) (func(), error) {
	runtime.LockOSThread()
	cmd.SysProcAttr = processAttributes()
	if err := cmd.Start(); err != nil {
		runtime.UnlockOSThread()
		return nil, err
	}
	var once sync.Once
	return func() { once.Do(func() { syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL); runtime.UnlockOSThread() }) }, nil
}

func signalStop(cmd *exec.Cmd) { syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) }
