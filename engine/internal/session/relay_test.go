package session

import (
	"bytes"
	"context"
	"io"
	"net"
	"testing"
	"time"
)

func TestRelayCountsBothDirectionsAndReleasesSockets(t *testing.T) {
	relay, err := newRelays("127.0.0.1:0", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address, _ := relay.addresses()
	public := relay.public[0].Addr().String()
	relay.releaseBackend()
	backend, err := net.Listen("tcp", address)
	if err != nil {
		t.Fatal(err)
	}
	defer backend.Close()
	go func() {
		connection, err := backend.Accept()
		if err != nil {
			return
		}
		defer connection.Close()
		io.Copy(connection, connection)
	}()
	relay.start()
	client, err := net.DialTimeout("tcp", public, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	client.SetDeadline(time.Now().Add(2 * time.Second))
	payload := bytes.Repeat([]byte("реальные байты"), 10000)
	go func() { client.Write(payload); client.(*net.TCPConn).CloseWrite() }()
	answer, err := io.ReadAll(client)
	client.Close()
	if err != nil || !bytes.Equal(answer, payload) {
		t.Fatal("данные изменены", err)
	}
	relay.close()
	snapshot := relay.snapshot()
	if snapshot.Download != int64(len(payload)) || snapshot.Upload != int64(len(payload)) {
		t.Fatalf("неверные счётчики: %+v", snapshot)
	}
	free, err := net.Listen("tcp", public)
	if err != nil {
		t.Fatal("порт остался занят", err)
	}
	free.Close()
}

func TestExplicitHealthRecheck(t *testing.T) {
	manager, _ := testManager(t)
	checked := make(chan struct{}, 4)
	manager.check = func(ctx context.Context, _ string) error {
		checked <- struct{}{}
		return nil
	}
	if manager.Check() == nil {
		t.Fatal("проверка разрешена без сессии")
	}
	if err := manager.Start(Request{Family: "xray", Configuration: `{"outbounds":[]}`}); err != nil {
		t.Fatal(err)
	}
	waitState(t, manager, "running")
	select {
	case <-checked:
	case <-time.After(time.Second):
		t.Fatal("нет первой проверки")
	}
	// Результат первой проверки должен попасть в состояние до повторного запроса.
	deadline := time.Now().Add(time.Second)
	for manager.Status().Connectivity != "verified" && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if err := manager.Check(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-checked:
	case <-time.After(time.Second):
		t.Fatal("повторная проверка не запущена")
	}
}
