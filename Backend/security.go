package main

import (
	"log"
	"net"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

const (
	MaxWebSocketMessageSize = 1 * 1024 * 1024 // 1 MiB
)

type ConnectionLimiter struct {
	mu                 sync.Mutex
	currentConnections int32
	maxConnections     int32
}

func NewConnectionLimiter(maxConnections int32) *ConnectionLimiter {
	return &ConnectionLimiter{
		maxConnections: maxConnections,
	}
}

func (l *ConnectionLimiter) Acquire() bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.currentConnections >= l.maxConnections {
		log.Printf("Connection limit exceeded: current=%d, max=%d", l.currentConnections, l.maxConnections)
		return false
	}

	l.currentConnections++
	return true
}

func (l *ConnectionLimiter) Release() {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.currentConnections > 0 {
		l.currentConnections--
	}
}

type LoginRateLimiter struct {
	mu                 sync.Mutex
	loginRate          float64
	loginBurst         int32
	loginBlockDuration time.Duration
	clients            map[string]*loginAttempt
}

type loginAttempt struct {
	limiter    *rate.Limiter
	failures   int32
	blockedTil time.Time
}

func NewLoginRateLimiter(
	loginRate float64,
	loginBurst int32,
	loginBlockDuration time.Duration,
) *LoginRateLimiter {
	return &LoginRateLimiter{
		loginRate:          loginRate,
		loginBurst:         loginBurst,
		loginBlockDuration: loginBlockDuration,
		clients:            make(map[string]*loginAttempt),
	}
}

func (l *LoginRateLimiter) get(ip string) *loginAttempt {
	entry, ok := l.clients[ip]
	if !ok {
		entry = &loginAttempt{
			limiter: rate.NewLimiter(
				rate.Limit(l.loginRate),
				int(l.loginBurst),
			),
		}

		l.clients[ip] = entry
	}

	return entry
}

func (l *LoginRateLimiter) Allow(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	entry := l.get(ip)

	if time.Now().Before(entry.blockedTil) {
		log.Printf("Login attempt rejected: IP %s is currently blocked until %v", ip, entry.blockedTil)
		return false
	}

	if !entry.limiter.Allow() {
		log.Printf("Login rate limit exceeded for IP %s", ip)
		return false
	}

	return true
}

func (l *LoginRateLimiter) Failed(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()

	entry := l.get(ip)

	entry.failures++

	if entry.failures >= l.loginBurst {
		entry.blockedTil = time.Now().Add(l.loginBlockDuration)
		entry.failures = 0
		log.Printf("IP %s exceeded max login failures and is blocked for %v", ip, l.loginBlockDuration)
	}
}

func (l *LoginRateLimiter) Success(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()

	delete(l.clients, ip)
}

func ExtractClientIP(conn net.Conn) string {
	if conn == nil {
		return "unknown"
	}

	host, _, err := net.SplitHostPort(conn.RemoteAddr().String())
	if err != nil {
		return conn.RemoteAddr().String()
	}

	return host
}
