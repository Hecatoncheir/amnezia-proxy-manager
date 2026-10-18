//go:build !windows

package localprofile

import "errors"

func ReadActive() ([]byte, error) {
	return nil, errors.New("локальный импорт AmneziaVPN пока доступен только в Windows")
}
