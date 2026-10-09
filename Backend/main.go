package main

import (
	"embed"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"net/url"
	"strings"

	"github.com/gorilla/websocket"
)

func createUpgrader(cfg *Config) websocket.Upgrader {
	return websocket.Upgrader{
		ReadBufferSize:  4096,
		WriteBufferSize: 4096,

		CheckOrigin: func(r *http.Request) bool {
			originHeader := r.Header.Get("Origin")

			// Non-browser clients such as Flutter Android/Windows
			if originHeader == "" {
				return true
			}

			parsedURL, err := url.Parse(originHeader)
			if err != nil {
				return false
			}

			schemeMatched := false
			for _, proto := range cfg.CorsProtocols {
				if strings.EqualFold(parsedURL.Scheme, proto) {
					schemeMatched = true
					break
				}
			}
			if !schemeMatched {
				return false
			}

			hostname := parsedURL.Hostname()
			for _, allowedHost := range cfg.CorsOrigins {
				if strings.EqualFold(hostname, allowedHost) {
					return true
				}
			}

			return false
		},
	}
}

//go:embed all:web
var flutterWebFS embed.FS

func main() {
	cfg := LoadConfig()

	db, err := InitDB("password_manager.db")
	if err != nil {
		log.Fatalf("Database initialization failed: %v", err)
	}

	serverIdentity, err := LoadServerPEM(
		cfg.ServerCertPEM,
		cfg.ServerKeyPEM,
	)
	if err != nil {
		log.Fatalf("Failed to load server identity: %v", err)
	}

	upgrader := createUpgrader(cfg)

	connectionLimiter := NewConnectionLimiter(cfg.SessionMaxConnections)
	loginLimiter := NewLoginRateLimiter(cfg.LoginRate, cfg.LoginBurst, cfg.LoginBlockDuration)

	http.HandleFunc("/ws", func(
		w http.ResponseWriter,
		r *http.Request,
	) {
		if !connectionLimiter.Acquire() {
			http.Error(w, "too many connections", http.StatusServiceUnavailable)
			log.Printf("WebSocket connection rejected: connection limit reached")
			return
		}

		defer connectionLimiter.Release()

		// Upgrade HTTP -> WebSocket.
		ws, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("WebSocket upgrade failed: %v", err)
			return
		}

		defer ws.Close()

		clientIP := ExtractClientIP(ws.UnderlyingConn())

		log.Printf("WebSocket connection accepted from %s", clientIP)

		session, err := PerformHandshake(
			ws,
			cfg.SessionReadTimeout,
			cfg.SessionWriteTimeout,
			cfg.SessionHandshakeTimeout,
			cfg.SessionIdleTimeout,
			serverIdentity,
			clientIP,
		)
		if err != nil {
			log.Printf("WebSocket handshake failed from %s: %v", clientIP, err)
			return
		}
		log.Printf("WebSocket handshake completed for %s", clientIP)

		HandleSession(session, db, loginLimiter)
		log.Printf("WebSocket connection closed for %s", clientIP)
	})

	subFS, err := fs.Sub(flutterWebFS, "web")
	if err != nil {
		log.Fatalf("Failed to create sub filesystem: %v", err)
	}

	fileServer := http.FileServer(http.FS(subFS))

	http.HandleFunc("/", func(
		w http.ResponseWriter,
		r *http.Request,
	) {
		path := strings.TrimPrefix(r.URL.Path, "/")

		if path == "" {
			fileServer.ServeHTTP(w, r)
			return
		}

		f, err := subFS.Open(path)
		if err != nil {
			r.URL.Path = "/"
			fileServer.ServeHTTP(w, r)
			return
		}

		f.Close()

		if strings.HasSuffix(path, ".js") || strings.HasSuffix(path, ".mjs") {
			w.Header().Set("Content-Type", "text/javascript")
		} else if strings.HasSuffix(path, ".wasm") {
			w.Header().Set("Content-Type", "application/wasm")
		} else if strings.HasSuffix(path, ".map") {
			w.Header().Set("Content-Type", "application/json")
		}

		fileServer.ServeHTTP(w, r)
	})

	addr := fmt.Sprintf("%s:%s", cfg.IP, cfg.Port)
	log.Printf("Server starting on ws://%s/ws", addr)
	log.Println()
	log.Printf("Network / CORS:")
	log.Printf("  - CORS Protocols: %v", cfg.CorsProtocols)
	log.Printf("  - CORS Origins:   %v", cfg.CorsOrigins)
	log.Println()
	log.Printf("Session & Timeouts:")
	log.Printf("  - Max Connections:    %d", cfg.SessionMaxConnections)
	log.Printf("  - Max Message Size:   %d", MaxWebSocketMessageSize)
	log.Printf("  - Read Timeout:       %v", cfg.SessionReadTimeout)
	log.Printf("  - Write Timeout:      %v", cfg.SessionWriteTimeout)
	log.Printf("  - Handshake Timeout:  %v", cfg.SessionHandshakeTimeout)
	log.Printf("  - Idle Timeout:       %v", cfg.SessionIdleTimeout)
	log.Println()
	log.Printf("Security & Rate Limiting:")
	log.Printf("  - Login Rate:         %.1f", cfg.LoginRate)
	log.Printf("  - Login Burst:        %d", cfg.LoginBurst)
	log.Printf("  - Login Block Dur.:   %v", cfg.LoginBlockDuration)
	log.Printf("  - Auth Token Life:    %v", cfg.AuthTokenLife)
	log.Printf("  - Token Clean Interv: %v", cfg.AuthTokenCleanInterval)

	GlobalTokenStore.Init(cfg.AuthTokenLife, cfg.AuthTokenCleanInterval)

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal("ListenAndServe error:", err)
	}
}
