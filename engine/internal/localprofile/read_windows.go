//go:build windows

// Package localprofile читает выбранный профиль только по явному действию пользователя.
package localprofile

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/binary"
	"encoding/json"
	"errors"
	"strings"
	"unicode/utf16"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

type credential struct {
	Flags, Type             uint32
	TargetName, Comment     *uint16
	LastWritten             windows.Filetime
	BlobSize                uint32
	Blob                    *byte
	Persist, AttributeCount uint32
	Attributes              uintptr
	TargetAlias, UserName   *uint16
}

func secret(tag string) ([]byte, error) {
	dll := windows.NewLazySystemDLL("advapi32.dll")
	name, _ := windows.UTF16PtrFromString(tag)
	var ptr *credential
	ok, _, err := dll.NewProc("CredReadW").Call(uintptr(unsafe.Pointer(name)), 1, 0, uintptr(unsafe.Pointer(&ptr)))
	if ok == 0 {
		return nil, err
	}
	defer dll.NewProc("CredFree").Call(uintptr(unsafe.Pointer(ptr)))
	if ptr.BlobSize > 4096 {
		return nil, errors.New("недопустимый размер ключа")
	}
	return append([]byte{}, unsafe.Slice(ptr.Blob, ptr.BlobSize)...), nil
}

func registryBytes(raw []byte) ([]byte, error) {
	if len(raw) > 2*1024*1024 {
		return nil, errors.New("слишком большое хранилище")
	}
	if strings.HasPrefix(string(raw), "EncData") {
		return raw, nil
	}
	if len(raw)%2 != 0 {
		return nil, errors.New("неизвестный формат реестра")
	}
	words := make([]uint16, len(raw)/2)
	for i := range words {
		words[i] = binary.LittleEndian.Uint16(raw[i*2:])
	}
	text := string(utf16.Decode(words))
	if !strings.HasPrefix(text, "@ByteArray(") || !strings.HasSuffix(text, ")") {
		return nil, errors.New("неизвестный формат Qt")
	}
	result := []byte{}
	for _, c := range text[11 : len(text)-1] {
		if c > 255 {
			return nil, errors.New("неизвестная кодировка Qt")
		}
		result = append(result, byte(c))
	}
	return result, nil
}

func decrypt(raw, key, iv []byte) ([]byte, error) {
	if !strings.HasPrefix(string(raw), "EncData") || len(key) != 32 || len(iv) != 32 {
		return nil, errors.New("несовместимое хранилище")
	}
	data := append([]byte{}, raw[7:]...)
	defer clear(data)
	if len(data) == 0 || len(data)%16 != 0 {
		return nil, errors.New("повреждённое хранилище")
	}
	block, _ := aes.NewCipher(key)
	cipher.NewCBCDecrypter(block, iv[:16]).CryptBlocks(data, data)
	padding := int(data[len(data)-1])
	if padding < 1 || padding > 16 {
		return nil, errors.New("повреждённое хранилище")
	}
	for _, b := range data[len(data)-padding:] {
		if int(b) != padding {
			return nil, errors.New("повреждённое хранилище")
		}
	}
	data = data[:len(data)-padding]
	if len(data) < 9 || binary.BigEndian.Uint32(data[:4]) != 12 {
		return nil, errors.New("неподдерживаемый QVariant")
	}
	length := int(binary.BigEndian.Uint32(data[5:9]))
	if length != len(data)-9 {
		return nil, errors.New("некорректная длина QVariant")
	}
	return append([]byte{}, data[9:]...), nil
}

// ReadActive не обращается к API Premium, не создаёт конфигурации и не меняет AmneziaVPN.
// В результат не включаются ключ подписки, auth_data или список других серверов.
func ReadActive() ([]byte, error) {
	reg, err := registry.OpenKey(registry.CURRENT_USER, `Software\AmneziaVPN.ORG\AmneziaVPN\Servers`, registry.QUERY_VALUE)
	if err != nil {
		return nil, errors.New("не найдена установка AmneziaVPN текущего пользователя")
	}
	defer reg.Close()
	raw, _, err := reg.GetBinaryValue("serversList")
	if err != nil {
		return nil, errors.New("нет сохранённых подключений AmneziaVPN")
	}
	raw, err = registryBytes(raw)
	if err != nil {
		return nil, err
	}
	key, err := secret("settingsKeyTag")
	if err != nil {
		return nil, errors.New("ключ AmneziaVPN недоступен текущей учётной записи")
	}
	defer clear(key)
	iv, err := secret("settingsIvTag")
	if err != nil {
		return nil, errors.New("IV AmneziaVPN недоступен")
	}
	defer clear(iv)
	data, err := decrypt(raw, key, iv)
	if err != nil {
		return nil, err
	}
	defer clear(data)
	id, _, err := reg.GetStringValue("defaultServerId")
	if err != nil {
		return nil, errors.New("не выбрано подключение AmneziaVPN")
	}
	return selected(data, id)
}

func selected(data []byte, id string) ([]byte, error) {
	var servers []map[string]any
	if json.Unmarshal(data, &servers) != nil || len(servers) > 100 {
		return nil, errors.New("неверный список подключений")
	}
	for _, server := range servers {
		if server["storageServerId"] != id {
			continue
		}
		containers, ok := server["containers"].([]any)
		if !ok {
			break
		}
		for _, item := range containers {
			container, ok := item.(map[string]any)
			if !ok || container["container"] != server["defaultContainer"] {
				continue
			}
			if xray, ok := container["xray"].(map[string]any); ok {
				if config, ok := xray["last_config"].(string); ok && len(config) <= 65536 && json.Valid([]byte(config)) {
					return []byte(config), nil
				}
			}
			if _, ok := container["awg"].(map[string]any); ok {
				return json.Marshal(map[string]any{"defaultContainer": "amnezia-awg", "dns1": server["dns1"], "dns2": server["dns2"], "hostName": server["hostName"], "containers": []any{container}})
			}
		}
	}
	return nil, errors.New("нет сохранённой клиентской конфигурации VLESS или AmneziaWG")
}
