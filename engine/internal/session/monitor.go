package session

import (
	"context"
	"errors"
	"sync"
	"time"
)

func (m *Manager) Check() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.active == nil || m.state.Status != "running" {
		return errors.New("not_running")
	}
	select {
	case m.active.recheck <- struct{}{}:
	default:
	}
	return nil
}

func (m *Manager) network(s *running) <-chan error {
	m.setRunning(s, "checking")
	address := m.socks
	result := make(chan error, 1)
	go func() {
		ctx, cancel := context.WithTimeout(s.ctx, 25*time.Second)
		defer cancel()
		result <- m.check(ctx, address)
	}()
	return result
}

func (m *Manager) reportTraffic(relay *relays) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.state.Traffic = relay.snapshot()
	if m.publish != nil {
		m.publish(m.state)
	}
}

func (m *Manager) networkResult(s *running, err error) {
	if s.ctx.Err() != nil {
		return
	}
	connectivity := "verified"
	if err != nil {
		connectivity = "unverified"
	}
	m.setRunning(s, connectivity)
}

func (m *Manager) setRunning(s *running, connectivity string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if s.ctx.Err() != nil || m.active != s {
		return
	}
	m.state = State{Status: "running", Connectivity: connectivity, Traffic: m.state.Traffic}
	if m.publish != nil {
		m.publish(m.state)
	}
}

func (m *Manager) watchNetwork(ctx context.Context, s *running) {
	result := m.network(s)
	for {
		select {
		case <-ctx.Done():
			return
		case <-s.recheck:
			result = m.startCheck(s, result)
		case err := <-result:
			m.networkResult(s, err)
			result = nil
		}
	}
}

func (m *Manager) startCheck(s *running, result <-chan error) <-chan error {
	if result != nil {
		return result
	}
	return m.network(s)
}

func requestCheck(s *running) {
	select {
	case s.recheck <- struct{}{}:
	default:
	}
}

func (m *Manager) sample(ctx context.Context, s *running, relay *relays) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	ticks := 0
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			ticks++
			m.sampleTick(s, relay, ticks)
		}
	}
}

func (m *Manager) sampleTick(s *running, relay *relays, ticks int) {
	m.reportTraffic(relay)
	if ticks%30 == 0 {
		requestCheck(s)
	}
}

func (m *Manager) monitor(s *running, exited <-chan error, relay *relays) (string, bool) {
	ctx, cancel := context.WithCancel(s.ctx)
	var workers sync.WaitGroup
	workers.Add(2)
	go func() { defer workers.Done(); m.watchNetwork(ctx, s) }()
	go func() { defer workers.Done(); m.sample(ctx, s, relay) }()
	defer func() { cancel(); workers.Wait() }()
	select {
	case <-s.ctx.Done():
		return "stopped", false
	case <-exited:
		return "engine_exited", true
	}
}
