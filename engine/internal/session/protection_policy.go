package session

import "runtime"

// В macOS подключённые подсети и привязка сокета к en0 обходят маршруты TUN.
// PF нужен в течение всего соединения, даже если блокировка после обрыва отключена.
func (r Request) trafficProtectionEnabled() bool {
	return r.KillSwitchEnabled() || (r.AllTraffic && runtime.GOOS == "darwin")
}

func (r Request) releaseTemporaryProtection(release func() error) error {
	if r.KillSwitchEnabled() || !r.trafficProtectionEnabled() {
		return nil
	}
	return release()
}

func (m *Manager) finishTemporaryProtection(r Request, code string) string {
	if err := r.releaseTemporaryProtection(m.clearProtection); err != nil {
		return "vpn_unblock_failed"
	}
	return code
}
