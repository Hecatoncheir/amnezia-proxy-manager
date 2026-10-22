//go:build darwin && cgo

package fullvpn

/*
#cgo LDFLAGS: -framework CoreFoundation -framework SystemConfiguration
#include <CoreFoundation/CoreFoundation.h>
#include <SystemConfiguration/SystemConfiguration.h>

static CFStringRef vpnDNSKey(void) {
    return CFSTR("State:/Network/Service/io.github.hecatoncheir.amneziaProxyManager/DNS");
}

static CFDictionaryRef vpnDNSConfiguration(void) {
    const void *address = CFSTR("172.31.255.2");
    const void *domain = CFSTR("");
    CFArrayRef addresses = CFArrayCreate(NULL, &address, 1, &kCFTypeArrayCallBacks);
    CFArrayRef domains = CFArrayCreate(NULL, &domain, 1, &kCFTypeArrayCallBacks);
    int order = 1;
    CFNumberRef searchOrder = CFNumberCreate(NULL, kCFNumberIntType, &order);
    const void *keys[] = {kSCPropNetDNSServerAddresses, kSCPropNetDNSSupplementalMatchDomains, kSCPropNetDNSSearchOrder};
    const void *values[] = {addresses, domains, searchOrder};
    CFDictionaryRef configuration = CFDictionaryCreate(NULL, keys, values, 3,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(addresses);
    CFRelease(domains);
    CFRelease(searchOrder);
    return configuration;
}

static SCDynamicStoreRef createVPNDNS(void) {
    const void *option = kSCDynamicStoreUseSessionKeys;
    const void *enabled = kCFBooleanTrue;
    CFDictionaryRef options = CFDictionaryCreate(NULL, &option, &enabled, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SCDynamicStoreRef store = SCDynamicStoreCreateWithOptions(NULL,
        CFSTR("Amnezia Proxy Manager VPN DNS"), options, NULL, NULL);
    CFRelease(options);
    if (!store) return NULL;
    CFDictionaryRef configuration = vpnDNSConfiguration();
    Boolean success = SCDynamicStoreSetValue(store, vpnDNSKey(), configuration);
    CFRelease(configuration);
    if (!success) {
        CFRelease(store);
        return NULL;
    }
    return store;
}

static void releaseVPNDNS(SCDynamicStoreRef store) {
    SCDynamicStoreRemoveValue(store, vpnDNSKey());
    CFRelease(store);
}
*/
import "C"

import (
	"errors"
	"sync"
)

// ConfigureDNS создаёт временный резолвер через TUN. Постоянные настройки
// сетевых служб не меняются; configd удалит ключ и при гибели supervisor.
func ConfigureDNS() (func(), error) {
	store := C.createVPNDNS()
	if store == 0 {
		return nil, errors.New("vpn_dns_failed")
	}
	var once sync.Once
	return func() { once.Do(func() { C.releaseVPNDNS(store) }) }, nil
}
