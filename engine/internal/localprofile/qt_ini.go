package localprofile

import (
	"errors"
	"io"
	"os"
	"strconv"
	"strings"
)

const maxSettingsSize = 2 * 1024 * 1024

func readQtSettings(path string) ([]byte, string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, "", err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxSettingsSize+1))
	if err != nil || len(data) > maxSettingsSize {
		return nil, "", errors.New("слишком большое хранилище")
	}
	defer clear(data)
	return parseQtSettings(string(data))
}

func parseQtSettings(text string) ([]byte, string, error) {
	text = strings.TrimPrefix(text, "\ufeff")
	values := map[string]string{}
	group := ""
	for _, line := range strings.Split(text, "\n") {
		group = qtIniLine(group, strings.TrimSpace(line), values)
	}
	raw, err := decodeQtValue(values["serversList"])
	if err != nil {
		return nil, "", err
	}
	id, err := decodeQtValue(values["defaultServerId"])
	if err != nil || len(id) == 0 {
		clear(raw)
		return nil, "", errors.New("не выбрано подключение AmneziaVPN")
	}
	return raw, string(id), nil
}

func qtIniLine(group, line string, values map[string]string) string {
	if strings.HasPrefix(line, "[") {
		return strings.TrimSuffix(strings.TrimPrefix(line, "["), "]")
	}
	if group != "Servers" {
		return group
	}
	key, value, ok := strings.Cut(line, "=")
	if ok {
		values[strings.TrimSpace(key)] = strings.TrimSpace(value)
	}
	return group
}

func qtUnwrap(text, prefix, suffix string) string {
	if !strings.HasPrefix(text, prefix) || !strings.HasSuffix(text, suffix) {
		return text
	}
	if len(text) < len(prefix)+len(suffix) {
		return text
	}
	return text[len(prefix) : len(text)-len(suffix)]
}

func decodeQtValue(text string) ([]byte, error) {
	text = qtUnwrap(text, `"`, `"`)
	text = qtUnwrap(text, "@ByteArray(", ")")
	result := make([]byte, 0, len(text))
	for index := 0; index < len(text); index++ {
		value, next, err := qtByte(text, index)
		if err != nil {
			clear(result)
			return nil, err
		}
		index = next
		result = append(result, value)
	}
	return result, nil
}

func qtByte(text string, index int) (byte, int, error) {
	if text[index] != '\\' {
		return text[index], index, nil
	}
	return qtEscape(text, index+1)
}

func qtEscape(text string, index int) (byte, int, error) {
	if index >= len(text) {
		return 0, index, errors.New("обрыв строки Qt")
	}
	escapes := map[byte]byte{'0': 0, 'a': 7, 'b': 8, 'f': 12, 'n': 10, 'r': 13, 't': 9, 'v': 11, '\\': '\\', '"': '"'}
	if value, ok := escapes[text[index]]; ok {
		return value, index, nil
	}
	if text[index] != 'x' {
		return 0, index, errors.New("неизвестная escape-последовательность Qt")
	}
	return qtHex(text, index+1)
}

func qtHex(text string, start int) (byte, int, error) {
	end := start
	for end < len(text) && end-start < 2 && strings.ContainsRune("0123456789abcdefABCDEF", rune(text[end])) {
		end++
	}
	value, err := strconv.ParseUint(text[start:end], 16, 8)
	return byte(value), end - 1, err
}
