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
		log.Fatalf(
			"Database initialization failed: %v",
			err,
		)
	}

	serverIdentity, err := LoadServerPEM(
		cfg.ServerCertPEM,
		cfg.ServerKeyPEM,
	)
	if err != nil {
		log.Fatalf("Failed to load server identity: %v", err)
	}

	upgrader := createUpgrader(cfg)

	connectionLimiter := NewConnectionLimiter(int(cfg.MaxWebSocketConnections))
	loginLimiter := NewLoginRateLimiter()

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
			cfg.SessionIdleTimeoutMins,
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
		path := strings.TrimPrefix(
			r.URL.Path,
			"/",
		)

		// Serve index.html for the root.
		if path == "" {
			fileServer.ServeHTTP(w, r)
			return
		}

		// Check whether the requested file actually exists.
		f, err := subFS.Open(path)
		if err != nil {
			r.URL.Path = "/"
			fileServer.ServeHTTP(w, r)
			return
		}

		f.Close()

		if strings.HasSuffix(path, ".js") || strings.HasSuffix(path, ".mjs") {
			w.Header().Set(
				"Content-Type",
				"text/javascript",
			)
		} else if strings.HasSuffix(path, ".wasm") {
			w.Header().Set(
				"Content-Type",
				"application/wasm",
			)
		}

		fileServer.ServeHTTP(w, r)
	})

	addr := fmt.Sprintf("%s:%s", cfg.IP, cfg.Port)

	log.Printf("Server starting on ws://%s/ws", addr)
	log.Printf(
		"CORS Protocols: %v | CORS Origins: %v | Session Idle Timeout: %f mins",
		cfg.CorsProtocols,
		cfg.CorsOrigins,
		cfg.SessionIdleTimeoutMins,
	)
	log.Printf("Maximum WebSocket message size: %d bytes", MaxWebSocketMessageSize)
	log.Printf("Maximum WebSocket connections: %d", cfg.MaxWebSocketConnections)

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(
			"ListenAndServe error:",
			err,
		)
	}
}
