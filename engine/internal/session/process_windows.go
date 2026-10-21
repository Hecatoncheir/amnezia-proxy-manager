package session

import (
	"golang.org/x/sys/windows"
	"os/exec"
	"sync"
	"syscall"
	"unsafe"
)

// Job наследуется дочерними процессами; гибель supervisor завершает всё дерево.
func GuardSupervisor() error {
	job, err := newJob()
	if err != nil {
		return err
	}
	if err = windows.AssignProcessToJobObject(job, windows.CurrentProcess()); err != nil {
		windows.CloseHandle(job)
		return err
	}
	// Дескриптор принадлежит процессу до его завершения, не передаётся детям.
	return nil
}
func newJob() (windows.Handle, error) {
	job, err := windows.CreateJobObject(nil, nil)
	if err != nil {
		return 0, err
	}
	info := windows.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	info.BasicLimitInformation.LimitFlags = windows.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	_, err = windows.SetInformationJobObject(job, windows.JobObjectExtendedLimitInformation, uintptr(unsafe.Pointer(&info)), uint32(unsafe.Sizeof(info)))
	if err != nil {
		windows.CloseHandle(job)
		return 0, err
	}
	return job, nil
}
func startProcess(cmd *exec.Cmd) (func(), error) {
	return startProcessWithFlags(cmd, 0)
}

func startTunnelProcess(cmd *exec.Cmd) (func(), error) {
	return startProcessWithFlags(cmd, windows.CREATE_NEW_PROCESS_GROUP)
}

func signalTunnelStop(cmd *exec.Cmd) {
	windows.GenerateConsoleCtrlEvent(windows.CTRL_BREAK_EVENT, uint32(cmd.Process.Pid))
}

func startProcessWithFlags(cmd *exec.Cmd, flags uint32) (func(), error) {
	job, err := newJob()
	if err != nil {
		return nil, err
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: windows.CREATE_SUSPENDED | flags}
	if err = cmd.Start(); err != nil {
		windows.CloseHandle(job)
		return nil, err
	}
	process, err := windows.OpenProcess(windows.PROCESS_SET_QUOTA|windows.PROCESS_TERMINATE|windows.PROCESS_SUSPEND_RESUME, false, uint32(cmd.Process.Pid))
	if err == nil {
		err = windows.AssignProcessToJobObject(job, process)
	}
	if err == nil {
		status, _, _ := windows.NewLazySystemDLL("ntdll.dll").NewProc("NtResumeProcess").Call(uintptr(process))
		if status != 0 {
			err = syscall.EINVAL
		}
	}
	if process != 0 {
		windows.CloseHandle(process)
	}
	if err != nil {
		cmd.Process.Kill()
		cmd.Wait()
		windows.CloseHandle(job)
		return nil, err
	}
	var once sync.Once
	return func() { once.Do(func() { windows.TerminateJobObject(job, 1); windows.CloseHandle(job) }) }, nil
}

func signalStop(cmd *exec.Cmd) { cmd.Process.Kill() }
