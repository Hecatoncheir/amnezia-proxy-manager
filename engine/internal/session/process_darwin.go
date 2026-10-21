package session

import (
	"os"
	"os/exec"
	"sync"
	"syscall"
)

// Канал закрывается ядром и при аварии supervisor. Наблюдатель завершает группу,
// поскольку macOS не предоставляет Linux Pdeathsig.
const parentGuardScript = `
group=$$
(
 trap '' TERM INT HUP
 IFS= read -r ignored <&3
 kill -TERM -- "-$group" 2>/dev/null
 /bin/sleep 2
 kill -KILL -- "-$group" 2>/dev/null
) &
watch=$!
"$@" &
child=$!
trap 'kill -TERM "$child" 2>/dev/null' TERM INT HUP
status=0
wait "$child" || status=$?
if kill -0 "$child" 2>/dev/null; then
 wait "$child"
 status=$?
fi
kill -KILL "$watch" 2>/dev/null
wait "$watch" 2>/dev/null
exit "$status"
`

func GuardSupervisor() error { return nil }

func startProcess(cmd *exec.Cmd) (func(), error) {
	input, control, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	original := append([]string{cmd.Path}, cmd.Args[1:]...)
	cmd.Path = "/bin/sh"
	cmd.Args = append([]string{"/bin/sh", "-c", parentGuardScript, "apm-parent-guard"}, original...)
	cmd.ExtraFiles = append([]*os.File{input}, cmd.ExtraFiles...)
	cmd.SysProcAttr = processAttributes()
	err = cmd.Start()
	input.Close()
	if err != nil {
		control.Close()
		return nil, err
	}
	var once sync.Once
	return func() { once.Do(func() { control.Close(); syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }) }, nil
}

func signalStop(cmd *exec.Cmd) { syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) }
