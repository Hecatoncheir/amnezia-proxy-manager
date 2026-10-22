package session

import (
	"errors"
	"runtime"
	"testing"
)

func TestConnectedProtectionPolicy(t *testing.T) {
	disabled := false
	for _, test := range []struct {
		name    string
		request Request
		protect bool
		release bool
	}{
		{"proxy", Request{}, false, false},
		{"persistent", Request{AllTraffic: true}, true, false},
		{"temporary", Request{AllTraffic: true, KillSwitch: &disabled}, runtime.GOOS == "darwin", runtime.GOOS == "darwin"},
	} {
		t.Run(test.name, func(t *testing.T) {
			checkProtectionPolicy(t, test.request, test.protect, test.release)
		})
	}
}

func TestTemporaryProtectionReleaseFailure(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("временная фильтрация macOS")
	}
	disabled := false
	request := Request{AllTraffic: true, KillSwitch: &disabled}
	failure := errors.New("release failed")
	if err := request.releaseTemporaryProtection(func() error { return failure }); !errors.Is(err, failure) {
		t.Fatal("ошибка снятия фильтра потеряна")
	}
}

func checkProtectionPolicy(t *testing.T, request Request, protect, release bool) {
	t.Helper()
	if request.trafficProtectionEnabled() != protect {
		t.Fatal("неверная фильтрация работающего VPN")
	}
	called := false
	err := request.releaseTemporaryProtection(func() error { called = true; return nil })
	if err != nil || called != release {
		t.Fatal("неверное сохранение защиты после остановки")
	}
}
