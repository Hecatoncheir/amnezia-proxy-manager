//go:build linux || darwin

package fullvpn

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"

	"golang.org/x/sys/unix"
)

const stateRoot = "/var/run/amnezia-proxy-manager"

func Supported() bool  { return BinaryHash("tun") != "" }
func Privileged() bool { return os.Geteuid() == 0 }

func Environment(directory string) ([]string, error) {
	return []string{"PATH=/usr/sbin:/usr/bin:/sbin:/bin", "HOME=" + directory, "TMPDIR=" + directory, "LANG=C", "LC_ALL=C"}, nil
}

func secureStateRoot() error {
	if !Privileged() {
		return errors.New("vpn_admin_required")
	}
	if err := createStateRoot(); err != nil {
		return err
	}
	info, err := os.Lstat(stateRoot)
	if err != nil {
		return err
	}
	if !secureRootDirectory(info) {
		return errors.New("private_config_failed")
	}
	return nil
}

func createStateRoot() error {
	if err := os.Mkdir(stateRoot, 0700); err != nil && !os.IsExist(err) {
		return err
	}
	return nil
}

func secureRootDirectory(info os.FileInfo) bool {
	stat, ok := info.Sys().(*syscall.Stat_t)
	return ok && stat.Uid == 0 && info.IsDir() && info.Mode().Perm() == 0700
}

func ProtectedDirectory() (string, error) {
	if err := secureStateRoot(); err != nil {
		return "", err
	}
	return os.MkdirTemp(stateRoot, "session-")
}

func Lock() (func(), error) {
	if err := secureStateRoot(); err != nil {
		return nil, err
	}
	descriptor, err := unix.Open(filepath.Join(stateRoot, "vpn.lock"), unix.O_CREAT|unix.O_RDWR|unix.O_CLOEXEC|unix.O_NOFOLLOW, 0600)
	if err != nil {
		return nil, err
	}
	if err := unix.Flock(descriptor, unix.LOCK_EX|unix.LOCK_NB); err != nil {
		unix.Close(descriptor)
		return nil, errors.New("vpn_already_running")
	}
	return func() { unix.Close(descriptor) }, nil
}
