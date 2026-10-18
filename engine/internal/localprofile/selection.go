package localprofile

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/binary"
	"encoding/json"
	"errors"
	"strings"
)

var invalidStorage = errors.New("повреждённое хранилище")
var missingProfile = errors.New("нет сохранённой клиентской конфигурации VLESS или AmneziaWG")

func decrypt(raw, key, iv []byte) ([]byte, error) {
	if !strings.HasPrefix(string(raw), "EncData") {
		return nil, invalidStorage
	}
	if len(key) != 32 || len(iv) != 32 {
		return nil, invalidStorage
	}
	data, err := decryptBlocks(raw[7:], key, iv)
	if err != nil {
		return nil, err
	}
	defer clear(data)
	return decodeVariant(data)
}

func decryptBlocks(raw, key, iv []byte) ([]byte, error) {
	if len(raw) == 0 || len(raw)%16 != 0 {
		return nil, invalidStorage
	}
	data := append([]byte{}, raw...)
	block, _ := aes.NewCipher(key)
	cipher.NewCBCDecrypter(block, iv[:16]).CryptBlocks(data, data)
	unpadded, err := unpad(data)
	if err != nil {
		clear(data)
		return nil, err
	}
	return unpadded, nil
}

func paddingLength(data []byte) (int, error) {
	if len(data) == 0 {
		return 0, invalidStorage
	}
	padding := int(data[len(data)-1])
	if padding < 1 || padding > 16 || padding > len(data) {
		return 0, invalidStorage
	}
	return padding, nil
}

func unpad(data []byte) ([]byte, error) {
	padding, err := paddingLength(data)
	if err != nil {
		return nil, err
	}
	for _, value := range data[len(data)-padding:] {
		if int(value) != padding {
			return nil, invalidStorage
		}
	}
	return data[:len(data)-padding], nil
}

func decodeVariant(data []byte) ([]byte, error) {
	if len(data) < 9 || binary.BigEndian.Uint32(data[:4]) != 12 {
		return nil, invalidStorage
	}
	length := int(binary.BigEndian.Uint32(data[5:9]))
	if length != len(data)-9 {
		return nil, invalidStorage
	}
	return append([]byte{}, data[9:]...), nil
}

func selected(data []byte, id string) ([]byte, error) {
	if id == "" {
		return nil, missingProfile
	}
	servers, err := serverList(data)
	if err != nil {
		return nil, err
	}
	for _, server := range servers {
		if server["storageServerId"] == id {
			return serverProfile(server)
		}
	}
	return nil, missingProfile
}

func serverList(data []byte) ([]map[string]any, error) {
	var servers []map[string]any
	if json.Unmarshal(data, &servers) != nil || len(servers) > 100 {
		return nil, invalidStorage
	}
	return servers, nil
}

func serverProfile(server map[string]any) ([]byte, error) {
	containers, ok := server["containers"].([]any)
	if !ok {
		return nil, missingProfile
	}
	name, ok := server["defaultContainer"].(string)
	if !ok {
		return nil, missingProfile
	}
	container, err := selectedContainer(containers, name)
	if err != nil {
		return nil, err
	}
	return containerProfile(container, server)
}

func selectedContainer(containers []any, name string) (map[string]any, error) {
	for _, item := range containers {
		container, ok := item.(map[string]any)
		if ok && container["container"] == name {
			return container, nil
		}
	}
	return nil, missingProfile
}

func containerProfile(container, server map[string]any) ([]byte, error) {
	if xray, ok := container["xray"].(map[string]any); ok {
		return xrayProfile(xray)
	}
	if _, ok := container["awg"].(map[string]any); ok {
		return json.Marshal(map[string]any{"defaultContainer": "amnezia-awg", "dns1": server["dns1"], "dns2": server["dns2"], "hostName": server["hostName"], "containers": []any{container}})
	}
	return nil, missingProfile
}

func xrayProfile(xray map[string]any) ([]byte, error) {
	config, ok := xray["last_config"].(string)
	if ok && len(config) <= 65536 && json.Valid([]byte(config)) {
		return []byte(config), nil
	}
	return nil, missingProfile
}
