//go:build !windows && !linux && !darwin

package localprofile

import "errors"

const Supported = false

func ReadActive() ([]byte, error) {
	return nil, errors.New("локальный импорт AmneziaVPN пока доступен только в Windows")
}
