package fullvpn

import (
	"errors"
	"net"
	"net/netip"
	"path/filepath"
	"unsafe"

	"github.com/tailscale/wf"
	"golang.org/x/sys/windows"
)

var sublayer = wf.SublayerID(windows.GUID{Data1: 0x2384ae12, Data2: 0x354c, Data3: 0x44c0, Data4: [8]byte{0x89, 0x33, 0x10, 0x3a, 0x67, 0x88, 0x90, 0xe1}})

func Supported() bool  { return true }
func Privileged() bool { return windows.GetCurrentProcessToken().IsElevated() }

func IsProtected() bool {
	if !Privileged() {
		return false
	}
	s, err := firewall()
	if err != nil {
		return true
	}
	defer s.Close()
	owned, err := ownedRules(s)
	return err != nil || owned[ruleID(1)] || owned[ruleID(11)]
}

func firewall() (*wf.Session, error) {
	return wf.New(&wf.Options{Name: "Amnezia Proxy Manager", Dynamic: false})
}

func ruleID(index uint32) wf.RuleID {
	guid := windows.GUID(sublayer)
	guid.Data1 += index
	return wf.RuleID(guid)
}

func ensureSublayer(s *wf.Session) error {
	layers, err := s.Sublayers()
	if err != nil {
		return err
	}
	for _, layer := range layers {
		if layer.ID == sublayer {
			return nil
		}
	}
	return s.AddSublayer(&wf.Sublayer{ID: sublayer, Name: "Amnezia Proxy Manager VPN", Weight: 65535})
}

func addRule(s *wf.Session, index uint32, layer wf.LayerID, action wf.Action, weight uint64, conditions ...*wf.Match) error {
	return s.AddRule(&wf.Rule{ID: ruleID(index), Name: "Amnezia Proxy Manager VPN", Layer: layer,
		Sublayer: sublayer, Action: action, Weight: weight, Conditions: conditions, HardAction: true})
}

func ownedRules(s *wf.Session) (map[wf.RuleID]bool, error) {
	rules, err := s.Rules()
	if err != nil {
		return nil, err
	}
	owned := make(map[wf.RuleID]bool)
	for _, rule := range rules {
		if rule.Sublayer == sublayer {
			owned[rule.ID] = true
		}
	}
	return owned, nil
}

func openRules() (*wf.Session, map[wf.RuleID]bool, error) {
	s, err := firewall()
	if err != nil {
		return nil, nil, err
	}
	owned, err := ownedRules(s)
	if err != nil {
		s.Close()
		return nil, nil, err
	}
	return s, owned, nil
}

// Правила переживают завершение supervisor, но не перезагрузку Windows.
// Сначала устанавливаем запрет, затем узкие исключения. Ошибка оставляет сеть закрытой.
func Protect(binary string, _ Plan) error {
	s, owned, err := openRules()
	if err != nil {
		return err
	}
	defer s.Close()
	if err := ensureSublayer(s); err != nil {
		return err
	}
	app, err := wf.AppID(binary)
	if err != nil {
		return err
	}
	return protectLayers(s, owned, app)
}

func protectLayers(s *wf.Session, owned map[wf.RuleID]bool, app string) error {
	for i, layer := range []wf.LayerID{wf.LayerALEAuthConnectV4, wf.LayerALEAuthConnectV6} {
		if err := protectLayer(s, owned, uint32(i)*10, layer, app); err != nil {
			return err
		}
	}
	return permitNetworkMaintenance(s, owned)
}

func protectLayer(s *wf.Session, owned map[wf.RuleID]bool, base uint32, layer wf.LayerID, app string) error {
	if err := ensureRule(s, owned, base+1, layer, wf.ActionBlock, 1); err != nil {
		return err
	}
	if err := ensureRule(s, owned, base+2, layer, wf.ActionPermit, 15,
		&wf.Match{Field: wf.FieldFlags, Op: wf.MatchTypeFlagsAllSet, Value: wf.ConditionFlagIsLoopback}); err != nil {
		return err
	}
	if err := deleteOwned(s, owned, base+3); err != nil {
		return err
	}
	return addRule(s, base+3, layer, wf.ActionPermit, 14,
		&wf.Match{Field: wf.FieldALEAppID, Op: wf.MatchTypeEqual, Value: app})
}

func ensureRule(s *wf.Session, owned map[wf.RuleID]bool, index uint32, layer wf.LayerID, action wf.Action, weight uint64, matches ...*wf.Match) error {
	if owned[ruleID(index)] {
		return nil
	}
	return addRule(s, index, layer, action, weight, matches...)
}

func deleteOwned(s *wf.Session, owned map[wf.RuleID]bool, index uint32) error {
	if !owned[ruleID(index)] {
		return nil
	}
	return s.DeleteRule(ruleID(index))
}

func permitNetworkMaintenance(s *wf.Session, owned map[wf.RuleID]bool) error {
	for i, ports := range [][2]uint16{{68, 67}, {546, 547}} {
		layer := []wf.LayerID{wf.LayerALEAuthConnectV4, wf.LayerALEAuthConnectV6}[i]
		if err := ensureRule(s, owned, uint32(20+i), layer, wf.ActionPermit, 12,
			&wf.Match{Field: wf.FieldIPProtocol, Op: wf.MatchTypeEqual, Value: uint8(17)},
			&wf.Match{Field: wf.FieldIPLocalPort, Op: wf.MatchTypeEqual, Value: ports[0]},
			&wf.Match{Field: wf.FieldIPRemotePort, Op: wf.MatchTypeEqual, Value: ports[1]}); err != nil {
			return err
		}
	}
	return permitNDP(s, owned)
}

func permitNDP(s *wf.Session, owned map[wf.RuleID]bool) error {
	for i, message := range []uint16{133, 134, 135, 136} {
		if err := permitNDPMessage(s, owned, uint32(30+i*2), message); err != nil {
			return err
		}
	}
	return nil
}

func permitNDPMessage(s *wf.Session, owned map[wf.RuleID]bool, base uint32, message uint16) error {
	for j, network := range []string{"fe80::/10", "ff02::/16"} {
		if err := ensureRule(s, owned, base+uint32(j), wf.LayerALEAuthConnectV6, wf.ActionPermit, 12,
			&wf.Match{Field: wf.FieldIPProtocol, Op: wf.MatchTypeEqual, Value: uint8(58)},
			&wf.Match{Field: wf.FieldIPLocalPort, Op: wf.MatchTypeEqual, Value: message},
			&wf.Match{Field: wf.FieldIPRemoteAddress, Op: wf.MatchTypeEqual, Value: netip.MustParsePrefix(network)}); err != nil {
			return err
		}
	}
	return nil
}

func AllowTunnel() error {
	luid, err := interfaceLUID()
	if err != nil {
		return err
	}
	s, owned, err := openRules()
	if err != nil {
		return err
	}
	defer s.Close()
	for i, layer := range []wf.LayerID{wf.LayerALEAuthConnectV4, wf.LayerALEAuthConnectV6} {
		if err := permitInterface(s, owned, uint32(i)*10+4, layer, luid); err != nil {
			return err
		}
	}
	return nil
}

func interfaceLUID() (uint64, error) {
	iface, err := net.InterfaceByName(InterfaceName)
	if err != nil {
		return 0, err
	}
	var luid uint64
	proc := windows.NewLazySystemDLL("iphlpapi.dll").NewProc("ConvertInterfaceIndexToLuid")
	result, _, _ := proc.Call(uintptr(iface.Index), uintptr(unsafe.Pointer(&luid)))
	if result != 0 {
		return 0, errors.New("vpn_interface_failed")
	}
	return luid, nil
}

func permitInterface(s *wf.Session, owned map[wf.RuleID]bool, index uint32, layer wf.LayerID, luid uint64) error {
	if err := deleteOwned(s, owned, index); err != nil {
		return err
	}
	return addRule(s, index, layer, wf.ActionPermit, 13, &wf.Match{Field: wf.FieldIPLocalInterface, Op: wf.MatchTypeEqual, Value: luid})
}

func Release() error {
	if !Privileged() {
		return nil
	}
	s, owned, err := openRules()
	if err != nil {
		return err
	}
	defer s.Close()
	// Убираем запреты последними: исключения при удалении не открывают утечки.
	for _, index := range []uint32{4, 14, 3, 13, 2, 12, 20, 21, 30, 31, 32, 33, 34, 35, 36, 37, 1, 11} {
		if err := deleteOwned(s, owned, index); err != nil {
			return err
		}
	}
	return nil
}

// Каталог не доступен для записи обычному процессу того же пользователя.
func ProtectedDirectory() (string, error) {
	root, err := windows.GetWindowsDirectory()
	if err != nil {
		return "", err
	}
	guid, err := windows.GenerateGUID()
	if err != nil {
		return "", err
	}
	directory := filepath.Join(root, "Temp", "amnezia-vpn-"+guid.String())
	descriptor, err := windows.SecurityDescriptorFromString("D:P(A;OICI;FA;;;BA)(A;OICI;FA;;;SY)")
	if err != nil {
		return "", err
	}
	name, err := windows.UTF16PtrFromString(directory)
	if err != nil {
		return "", err
	}
	attributes := windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), SecurityDescriptor: descriptor}
	err = windows.CreateDirectory(name, &attributes)
	return directory, err
}
