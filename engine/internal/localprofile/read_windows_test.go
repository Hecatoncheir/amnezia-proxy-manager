package localprofile

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/binary"
	"encoding/json"
	"strings"
	"testing"
	"unicode/utf16"
)

func TestSelectedExcludesSubscription(t *testing.T) {
	source := []byte(`[{"storageServerId":"chosen","defaultContainer":"amnezia-xray","auth_data":{"token":"SECRET-TOKEN"},"api_config":{"vpn_key":"SECRET-SUBSCRIPTION"},"containers":[{"container":"amnezia-xray","xray":{"last_config":"{\"outbounds\":[]}"}}]}]`)
	result, err := selected(source, "chosen")
	if err != nil {
		t.Fatal(err)
	}
	if !json.Valid(result) || strings.Contains(string(result), "SECRET") {
		t.Fatal("лишние данные перенесены")
	}
	if _, err := selected(source, "other"); err == nil {
		t.Fatal("принят другой сервер")
	}
}

func TestDecryptAndQtRegistryEncoding(t *testing.T) {
	payload := []byte(`[{"storageServerId":"test"}]`)
	plain := make([]byte, 9)
	binary.BigEndian.PutUint32(plain, 12)
	binary.BigEndian.PutUint32(plain[5:], uint32(len(payload)))
	plain = append(plain, payload...)
	pad := 16 - len(plain)%16
	for i := 0; i < pad; i++ {
		plain = append(plain, byte(pad))
	}
	key, iv := make([]byte, 32), make([]byte, 32)
	block, _ := aes.NewCipher(key)
	cipher.NewCBCEncrypter(block, iv[:16]).CryptBlocks(plain, plain)
	encrypted := append([]byte("EncData"), plain...)
	result, err := decrypt(encrypted, key, iv)
	if err != nil || string(result) != string(payload) {
		t.Fatal("неверная расшифровка")
	}
	chars := []rune("@ByteArray(")
	for _, b := range encrypted {
		chars = append(chars, rune(b))
	}
	chars = append(chars, ')')
	words := utf16.Encode(chars)
	raw := make([]byte, len(words)*2)
	for i, v := range words {
		binary.LittleEndian.PutUint16(raw[i*2:], v)
	}
	decoded, err := registryBytes(raw)
	if err != nil || string(decoded) != string(encrypted) {
		t.Fatal("неверное чтение Qt")
	}
	encrypted[len(encrypted)-1] ^= 1
	if _, err := decrypt(encrypted, key, iv); err == nil {
		t.Fatal("повреждённые данные приняты")
	}
}
