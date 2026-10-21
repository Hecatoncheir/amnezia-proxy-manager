package fullvpn

import (
	"errors"
	"runtime"

	"golang.org/x/sys/windows"
)

func Lock() (func(), error) {
	runtime.LockOSThread()
	handle, err := lockMutex()
	if err != nil {
		runtime.UnlockOSThread()
		return nil, err
	}
	return func() { windows.ReleaseMutex(handle); windows.CloseHandle(handle); runtime.UnlockOSThread() }, nil
}

func lockMutex() (windows.Handle, error) {
	name, _ := windows.UTF16PtrFromString(`Global\AmneziaProxyManagerFullVPN`)
	handle, err := windows.CreateMutex(nil, false, name)
	if err != nil && !errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		return 0, err
	}
	result, err := windows.WaitForSingleObject(handle, 0)
	if err != nil {
		windows.CloseHandle(handle)
		return 0, err
	}
	if !mutexAcquired(result) {
		windows.CloseHandle(handle)
		return 0, errors.New("vpn_already_running")
	}
	return handle, nil
}

func mutexAcquired(result uint32) bool {
	return result == windows.WAIT_OBJECT_0 || result == windows.WAIT_ABANDONED
}
