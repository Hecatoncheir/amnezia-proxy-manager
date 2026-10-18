//go:build !windows && !linux

package session

import "syscall"

func processAttributes() *syscall.SysProcAttr { return &syscall.SysProcAttr{Setpgid: true} }
