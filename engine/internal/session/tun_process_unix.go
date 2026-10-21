//go:build !windows

package session

import "os/exec"

func startTunnelProcess(cmd *exec.Cmd) (func(), error) { return startProcess(cmd) }
func signalTunnelStop(cmd *exec.Cmd)                   { signalStop(cmd) }
