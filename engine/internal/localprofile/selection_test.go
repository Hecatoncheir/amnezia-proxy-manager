package localprofile

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/binary"
	"testing"
)

func TestQtEncryptedVariant(t *testing.T) {
	payload := []byte(selectedFixture)
	plain := make([]byte, 9)
	binary.BigEndian.PutUint32(plain, 12)
	binary.BigEndian.PutUint32(plain[5:], uint32(len(payload)))
	plain = append(plain, payload...)
	padding := 16 - len(plain)%16
	for i := 0; i < padding; i++ {
		plain = append(plain, byte(padding))
	}
	key, iv := make([]byte, 32), make([]byte, 32)
	block, _ := aes.NewCipher(key)
	cipher.NewCBCEncrypter(block, iv[:16]).CryptBlocks(plain, plain)
	raw := append([]byte("EncData"), plain...)
	data, err := decrypt(raw, key, iv)
	if err != nil || string(data) != string(payload) {
		t.Fatal("не прочитан Qt QVariant", err)
	}
	if _, err := decrypt(raw, key[:16], iv); err == nil {
		t.Fatal("принят неверный ключ")
	}
	if _, err := decrypt(raw[:len(raw)-1], key, iv); err == nil {
		t.Fatal("принято оборванное хранилище")
	}
}

func TestMalformedSelection(t *testing.T) {
	for _, data := range []string{`[]`, `{}`, `[{"storageServerId":"chosen","containers":[]}]`, `[{"storageServerId":"chosen","defaultContainer":{},"containers":[{"container":{}}]}]`} {
		if _, err := selected([]byte(data), "chosen"); err == nil {
			t.Fatal("приняты повреждённые настройки")
		}
	}
	if _, err := selected([]byte(selectedFixture), ""); err == nil {
		t.Fatal("выбран профиль без идентификатора")
	}
}
