package session

import (
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

// Traffic учитывает TCP-байты локального прокси, включая его служебные заголовки.
type Traffic struct {
	Download int64 `json:"download"`
	Upload   int64 `json:"upload"`
}

type relays struct {
	public           []net.Listener
	backend          []net.Listener
	mu               sync.Mutex
	connections      map[net.Conn]bool
	closed           bool
	download, upload atomic.Int64
	workers          sync.WaitGroup
}

func newRelays(socks, http string) (*relays, error) {
	r := &relays{connections: make(map[net.Conn]bool)}
	for _, address := range []string{socks, http} {
		if err := r.reserve(address); err != nil {
			r.close()
			return nil, err
		}
	}
	return r, nil
}

func (r *relays) reserve(address string) error {
	public, err := net.Listen("tcp", address)
	if err != nil {
		return err
	}
	r.public = append(r.public, public)
	backend, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return err
	}
	r.backend = append(r.backend, backend)
	return nil
}

func (r *relays) addresses() (string, string) {
	return r.backend[0].Addr().String(), r.backend[1].Addr().String()
}

func (r *relays) releaseBackend() {
	for _, listener := range r.backend {
		listener.Close()
	}
}

func (r *relays) start() {
	for index, listener := range r.public {
		r.workers.Add(1)
		go r.accept(listener, r.backend[index].Addr().String())
	}
}

func (r *relays) accept(listener net.Listener, target string) {
	defer r.workers.Done()
	for {
		connection, err := listener.Accept()
		if err != nil {
			return
		}
		if !r.track(connection) {
			continue
		}
		r.workers.Add(1)
		go r.forward(connection, target)
	}
}

func (r *relays) track(connection net.Conn) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	// Ограничиваем число клиентских соединений и память supervisor.
	if r.closed || len(r.connections) >= 512 {
		connection.Close()
		return false
	}
	r.connections[connection] = true
	return true
}

func (r *relays) forget(connection net.Conn) {
	connection.Close()
	r.mu.Lock()
	delete(r.connections, connection)
	r.mu.Unlock()
}

func (r *relays) forward(client net.Conn, target string) {
	defer r.workers.Done()
	defer r.forget(client)
	upstream, err := net.DialTimeout("tcp", target, 2*time.Second)
	if err != nil {
		return
	}
	if !r.track(upstream) {
		return
	}
	defer r.forget(upstream)
	done := make(chan struct{})
	go func() {
		io.Copy(countWriter{upstream, &r.upload}, client)
		upstream.(*net.TCPConn).CloseWrite()
		close(done)
	}()
	io.Copy(countWriter{client, &r.download}, upstream)
	client.(*net.TCPConn).CloseWrite()
	<-done
}

type countWriter struct {
	io.Writer
	count *atomic.Int64
}

func (w countWriter) Write(data []byte) (int, error) {
	n, err := w.Writer.Write(data)
	w.count.Add(int64(n))
	return n, err
}

func (r *relays) snapshot() *Traffic {
	return &Traffic{Download: r.download.Load(), Upload: r.upload.Load()}
}

func (r *relays) close() {
	r.mu.Lock()
	r.closed = true
	for _, listener := range r.public {
		listener.Close()
	}
	for connection := range r.connections {
		connection.Close()
	}
	r.mu.Unlock()
	r.releaseBackend()
	r.workers.Wait()
}
