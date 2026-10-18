//go:build darwin && !cgo

package localprofile

import "errors"

const Supported = false

func ReadActive() ([]byte, error) {
	return nil, errors.New("для чтения Связки ключей нужна нативная сборка macOS")
}
