//go:build darwin && cgo

package localprofile

/*
#cgo LDFLAGS: -framework CoreFoundation -framework Security
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <string.h>
#include <stdlib.h>

static int copyData(CFTypeRef value, unsigned char *out, int capacity) {
    if (!value) return -1;
    int length = -1;
    if (CFGetTypeID(value) == CFDataGetTypeID()) {
        CFIndex count = CFDataGetLength((CFDataRef)value);
        if (count <= capacity) {
            memcpy(out, CFDataGetBytePtr((CFDataRef)value), count);
            length = (int)count;
        }
    } else if (CFGetTypeID(value) == CFStringGetTypeID()) {
        if (CFStringGetCString((CFStringRef)value, (char *)out, capacity, kCFStringEncodingUTF8))
            length = (int)strlen((char *)out);
    }
    CFRelease(value);
    return length;
}

static int readPreference(const char *name, unsigned char *out, int capacity) {
    CFStringRef key = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
    CFTypeRef value = CFPreferencesCopyValue(key, CFSTR("org.amneziavpn.AmneziaVPN"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(key);
    return copyData(value, out, capacity);
}

static int readSecret(const char *name, unsigned char *out, int capacity) {
    CFStringRef account = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
    const void *keys[] = {kSecClass, kSecAttrService, kSecAttrAccount, kSecReturnData};
    const void *values[] = {kSecClassGenericPassword, CFSTR("AmneziaVPN-Keychain"), account, kCFBooleanTrue};
    CFDictionaryRef query = CFDictionaryCreate(NULL, keys, values, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFTypeRef value = NULL;
    OSStatus status = SecItemCopyMatching(query, &value);
    CFRelease(query);
    CFRelease(account);
    if (status != errSecSuccess) return -1;
    return copyData(value, out, capacity);
}
*/
import "C"

import (
	"errors"
	"strings"
	"unsafe"
)

const Supported = true

func macPreference(name string, limit int) ([]byte, error) {
	key := C.CString(name)
	defer C.free(unsafe.Pointer(key))
	data := make([]byte, limit)
	size := int(C.readPreference(key, (*C.uchar)(unsafe.Pointer(&data[0])), C.int(limit)))
	if size < 0 {
		clear(data)
		return nil, errors.New("нет доступных настроек AmneziaVPN")
	}
	return data[:size], nil
}

func macSecret(name string) ([]byte, error) {
	key := C.CString(name)
	defer C.free(unsafe.Pointer(key))
	data := make([]byte, 32)
	if C.readSecret(key, (*C.uchar)(unsafe.Pointer(&data[0])), 32) != 32 {
		clear(data)
		return nil, errors.New("разрешите доступ к ключу AmneziaVPN в Связке ключей")
	}
	return data, nil
}

func ReadActive() ([]byte, error) {
	raw, err := macPreference("Servers.serversList", maxSettingsSize)
	if err != nil {
		return nil, err
	}
	defer clear(raw)
	id, err := macPreference("Servers.defaultServerId", 512)
	if err != nil {
		return nil, err
	}
	if !strings.HasPrefix(string(raw), "EncData") {
		return selected(raw, string(id))
	}
	data, err := decryptMac(raw)
	if err != nil {
		return nil, err
	}
	defer clear(data)
	return selected(data, string(id))
}

func decryptMac(raw []byte) ([]byte, error) {
	key, err := macSecret("settingsKeyTag")
	if err != nil {
		return nil, err
	}
	defer clear(key)
	iv, err := macSecret("settingsIvTag")
	if err != nil {
		return nil, err
	}
	defer clear(iv)
	return decrypt(raw, key, iv)
}
