package session

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/fullvpn"
	"io"
	"os"
	"os/signal"
	"sync"
	"syscall"
)

const MaxLine = 512 * 1024

// Serve использует только JSON Lines. stdout/stderr движка никогда не входят в IPC.
func Serve(input io.Reader, output io.Writer, vpnOnly ...bool) error {
	if GuardSupervisor() != nil {
		return errors.New("не удалось защитить дерево процессов")
	}
	cleanupOrphans()
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	return serveContext(ctx, input, output, vpnOnly...)
}
func serve(input io.Reader, output io.Writer) error {
	return serveContext(context.Background(), input, output)
}
func serveContext(ctx context.Context, input io.Reader, output io.Writer, vpnOnly ...bool) error {
	var writeMu sync.Mutex
	write := func(value any) { writeMu.Lock(); defer writeMu.Unlock(); json.NewEncoder(output).Encode(value) }
	manager := New(func(state State) { write(map[string]any{"version": 1, "event": "state", "state": state}) })
	manager.vpnOnly = len(vpnOnly) > 0 && vpnOnly[0]
	if manager.vpnOnly {
		manager.blocked = fullvpn.IsProtected()
	}
	defer manager.stop(true)
	finished := make(chan struct{})
	defer close(finished)
	go func() {
		select {
		case <-finished:
			return
		case <-ctx.Done():
			manager.stop(true)
			if closer, ok := input.(io.Closer); ok {
				closer.Close()
			}
		}
	}()
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), MaxLine)
	negotiated := false
	for scanner.Scan() {
		if ctx.Err() != nil {
			break
		}
		var request Request
		if json.Unmarshal(scanner.Bytes(), &request) != nil || request.Version != 1 || request.ID == "" || len(request.ID) > 64 {
			write(map[string]any{"version": 1, "requestId": "", "ok": false, "code": "invalid_request"})
			continue
		}
		response := map[string]any{"version": 1, "requestId": request.ID, "ok": true}
		var err error
		switch request.Method {
		case "hello":
			negotiated = true
			response["capabilities"] = []string{"start", "stop", "status", "custom_ports", "health_check", "traffic", "full_vpn", "kill_switch"}
			response["maxConfigBytes"] = 65536
			response["internetBlocked"] = manager.blocked
		case "status":
			if !negotiated {
				err = errors.New("handshake_required")
			} else {
				response["state"] = manager.Status()
			}
		case "start":
			if !negotiated {
				err = errors.New("handshake_required")
			} else {
				err = manager.Start(request)
			}
		case "check":
			if !negotiated {
				err = errors.New("handshake_required")
			} else {
				err = manager.Check()
			}
		case "stop":
			err = manager.stop(request.PreserveProtection)
			response["state"] = manager.Status()
		default:
			err = errors.New("unknown_method")
		}
		if err != nil {
			response["ok"] = false
			response["code"] = err.Error()
		}
		write(response)
	}
	// EOF, слишком длинная строка или потеря UI всегда останавливают сессию.
	return scanner.Err()
}
