package fullvpn

import "runtime"

var pinnedBinaries = map[string]map[string]string{
	"windows/amd64": {
		"awg":  "c5890fedddc63a97ad123e2d490edbf5fd2a0edfccbc7db99b1c53c72efcb2f3",
		"xray": "1d9674327972a21afd4c906a7a72bb0856935aa9e0227c87f34f03d11a88bddf", "tun": BinarySHA256,
	},
	"linux/amd64": {
		"awg":  "619f3e7b4aa6e9f6af38a826f30578d0e2eca9f932e93f518220884e9b7e10a6",
		"xray": "64d46afb80adea1bf97a0d467e83f4a9ac1ebd0995891e84bca3f1a1d1affb1d",
		"tun":  "768d31fa7f68debc067bb4626539498a1e8751d36a7b99e1a54bee6a23815f93",
	},
	"darwin/arm64": {
		"awg":  "8fa5940404a06c5b1e6f51cfb4ae59c88afcdc3a9da980dc57b6a3575494bb29",
		"xray": "bd4154efa640c5b8e21f10b68afcc9177c4f1f543be3ec0485b10c499b2a4b27",
		"tun":  "28b7200074d6380006acc4f035a404c8af3dceb65dd92d7386ed92c9224e08a2",
	},
}

func BinaryHash(family string) string { return pinnedBinaries[runtime.GOOS+"/"+runtime.GOARCH][family] }

func TunInterfaceName() string {
	switch runtime.GOOS {
	case "linux":
		return "apm-vpn"
	case "darwin":
		return "utun233"
	default:
		return InterfaceName
	}
}

func executableName(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}
	return name
}

func BackendName() string   { return executableName("vpn-backend") }
func TunBinaryName() string { return executableName("sing-box") }
