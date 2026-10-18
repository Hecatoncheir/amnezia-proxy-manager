package validation

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/upstream"
)

type probeLog struct {
	sync.Mutex
	data []byte
}

func (l *probeLog) Write(data []byte) (int, error) {
	l.Lock()
	defer l.Unlock()
	if len(l.data) < 65536 {
		remaining := 65536 - len(l.data)
		if remaining > len(data) {
			remaining = len(data)
		}
		l.data = append(l.data, data[:remaining]...)
	}
	return len(data), nil
}
func (l *probeLog) reason() string {
	l.Lock()
	defer l.Unlock()
	text := strings.ToLower(string(l.data))
	reasons := []string{}
	for _, word := range []string{"timeout", "certificate", "reality", "refused", "resolve", "xhttp", "failed to dial", "closed", "invalid"} {
		if strings.Contains(text, word) {
			reasons = append(reasons, word)
		}
	}
	clear(l.data)
	return strings.Join(reasons, ",")
}

func freePort() (int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port, nil
}

// ProbeXray — явная однократная диагностика HTTPS через отдельный SOCKS5.
// Не меняет системный прокси и не использует прямой fallback.
func ProbeXray(binary, sum string, input io.Reader) (result error) {
	if upstream.VerifyXrayBinary(binary, sum) != nil {
		return errors.New("Xray не прошёл проверку")
	}
	return probeXray(binary, input)
}

func probeXray(binary string, input io.Reader) (result error) {
	data, err := io.ReadAll(io.LimitReader(input, MaxConfig+1))
	if err != nil || len(data) > MaxConfig {
		return errors.New("неверный размер конфигурации")
	}
	defer clear(data)
	var config map[string]any
	if json.Unmarshal(data, &config) != nil {
		return errors.New("неверная конфигурация JSON")
	}
	config["log"] = map[string]any{"loglevel": "warning"}
	inbounds, ok := config["inbounds"].([]any)
	if !ok || len(inbounds) != 2 {
		return errors.New("неверные локальные входы")
	}
	socks, err := freePort()
	if err != nil {
		return errors.New("нет свободного порта")
	}
	httpPort, err := freePort()
	if err != nil {
		return errors.New("нет свободного порта")
	}
	for httpPort == socks {
		httpPort, err = freePort()
		if err != nil {
			return errors.New("нет свободного порта")
		}
	}
	for i, port := range []int{socks, httpPort} {
		inbound, ok := inbounds[i].(map[string]any)
		if !ok || inbound["listen"] != "127.0.0.1" {
			return errors.New("разрешён только loopback")
		}
		inbound["port"] = port
	}
	encoded, err := json.Marshal(config)
	if err != nil {
		return errors.New("неверный JSON")
	}
	defer clear(encoded)
	directory, err := privateDirectory()
	if err != nil {
		return errors.New("не удалось защитить конфигурацию")
	}
	defer func() {
		if os.RemoveAll(directory) != nil {
			result = errors.New("не удалось удалить конфигурацию")
		}
	}()
	path := filepath.Join(directory, "profile.json")
	if os.WriteFile(path, encoded, 0600) != nil {
		return errors.New("не удалось записать конфигурацию")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 35*time.Second)
	defer cancel()
	command, err := upstream.XrayCommand(ctx, binary, path, false)
	if err != nil {
		return errors.New("не удалось подготовить Xray")
	}
	logs := &probeLog{}
	defer func() { clear(logs.data) }()
	command.Stdout, command.Stderr = logs, logs
	if command.Start() != nil {
		return errors.New("не удалось запустить Xray")
	}
	defer func() { command.Process.Kill(); command.Wait() }()
	proxy := net.JoinHostPort("127.0.0.1", strconv.Itoa(socks))
	ready := false
	for i := 0; i < 50; i++ {
		connection, err := net.DialTimeout("tcp", proxy, 100*time.Millisecond)
		if err == nil {
			connection.Close()
			ready = true
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if !ready {
		return errors.New("SOCKS5 не открылся")
	}
	transport := &http.Transport{DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
		return socksDial(ctx, proxy, address)
	}}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 25 * time.Second}
	request, _ := http.NewRequestWithContext(ctx, "GET", "https://example.com/", nil)
	response, err := client.Do(request)
	if err != nil {
		reason := logs.reason()
		for _, word := range []string{"timeout", "eof", "reset", "tls", "handshake", "socks", "refused", "deadline"} {
			if strings.Contains(strings.ToLower(err.Error()), word) {
				reason += "," + word
			}
		}
		return errors.New("HTTPS через VLESS не прошёл; диагностика=" + reason)
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return errors.New("тестовый HTTPS-сервер ответил ошибкой")
	}
	_, err = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if err != nil {
		return errors.New("не удалось прочитать HTTPS-ответ")
	}
	return nil
}

func socksDial(ctx context.Context, proxy, address string) (net.Conn, error) {
	connection, err := (&net.Dialer{Timeout: 5 * time.Second}).DialContext(ctx, "tcp", proxy)
	if err != nil {
		return nil, err
	}
	success := false
	defer func() {
		if !success {
			connection.Close()
		}
	}()
	connection.SetDeadline(time.Now().Add(25 * time.Second))
	if _, err = connection.Write([]byte{5, 1, 0}); err != nil {
		return nil, err
	}
	answer := make([]byte, 2)
	if _, err = io.ReadFull(connection, answer); err != nil || answer[0] != 5 || answer[1] != 0 {
		return nil, errors.New("SOCKS negotiation")
	}
	host, portText, err := net.SplitHostPort(address)
	if err != nil || len(host) > 255 {
		return nil, errors.New("SOCKS address")
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		return nil, err
	}
	request := append([]byte{5, 1, 0, 3, byte(len(host))}, []byte(host)...)
	request = append(request, byte(port>>8), byte(port))
	if _, err = connection.Write(request); err != nil {
		return nil, err
	}
	header := make([]byte, 4)
	if _, err = io.ReadFull(connection, header); err != nil || header[0] != 5 || header[1] != 0 {
		return nil, errors.New("SOCKS connect")
	}
	length := 0
	switch header[3] {
	case 1:
		length = 4
	case 4:
		length = 16
	case 3:
		b := make([]byte, 1)
		if _, err = io.ReadFull(connection, b); err != nil {
			return nil, err
		}
		length = int(b[0])
	default:
		return nil, errors.New("SOCKS reply")
	}
	tail := make([]byte, length+2)
	if _, err = io.ReadFull(connection, tail); err != nil {
		return nil, err
	}
	if strings.Contains(host, "\x00") {
		return nil, errors.New("SOCKS hostname")
	}
	success = true
	return connection, nil
}
