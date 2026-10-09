package main

import (
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	IP            string
	Port          string
	ServerCertPEM string
	ServerKeyPEM  string
	CorsProtocols []string
	CorsOrigins   []string

	SessionReadTimeout      time.Duration
	SessionWriteTimeout     time.Duration
	SessionHandshakeTimeout time.Duration
	SessionIdleTimeout      time.Duration
	SessionMaxConnections   int32

	LoginRate          float64
	LoginBurst         int32
	LoginBlockDuration time.Duration

	AuthTokenLife          time.Duration
	AuthTokenCleanInterval time.Duration
}

func LoadConfig() *Config {
	return &Config{
		IP:   getEnv("SERVER_IP", "0.0.0.0"),
		Port: getEnv("SERVER_PORT", "8080"),
		ServerCertPEM: getEnv("SERVER_CERT_PEM", ""),
		ServerKeyPEM: getEnv("SERVER_KEY_PEM", ""),
		CorsProtocols: getEnvSlice("CORS_PROTOCOLS", "http;https;ws;wss", ";"),
		CorsOrigins:   getEnvSlice("CORS_ORIGINS", "localhost;127.0.0.1", ";"),

		SessionReadTimeout:      time.Duration(getEnvFloat64("SESSION_READ_TIMEOUT_SECS", 60.0) * float64(time.Second)),
		SessionWriteTimeout:     time.Duration(getEnvFloat64("SESSION_WRITE_TIMEOUT_SECS", 10.0) * float64(time.Second)),
		SessionHandshakeTimeout: time.Duration(getEnvFloat64("SESSION_HANDSHAKE_TIMEOUT_SECS", 10.0) * float64(time.Second)),
		SessionIdleTimeout:      time.Duration(getEnvFloat64("SESSION_IDLE_TIMEOUT_MINS", 5.0) * float64(time.Minute)),
		SessionMaxConnections:   getEnvInt32("SESSION_MAX_CONNECTIONS", 100),

		LoginRate:          getEnvFloat64("LOGIN_RATE", 5.0),
		LoginBurst:         getEnvInt32("LOGIN_BURST", 5),
		LoginBlockDuration: time.Duration(getEnvFloat64("LOGIN_BLOCK_DURATION_MINS", 5.0) * float64(time.Minute)),

		AuthTokenLife:          time.Duration(getEnvFloat64("AUTH_TOKEN_LIFE_MINS", 5.0) * float64(time.Minute)),
		AuthTokenCleanInterval: time.Duration(getEnvFloat64("AUTO_TOKEN_CLEAN_INTERVAL_MINS", 10.0) * float64(time.Minute)),
	}
}

func getEnv(key, fallback string) string {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		return val
	}
	return fallback
}

func getEnvSlice(key, fallback, sep string) []string {
	val := getEnv(key, fallback)
	items := strings.Split(val, sep)
	var result []string
	for _, item := range items {
		trimmed := strings.TrimSpace(item)
		if trimmed != "" {
			result = append(result, strings.ToLower(trimmed))
		}
	}
	return result
}

func getEnvInt32(key string, fallback int32) int32 {
	valStr := getEnv(key, "")
	if valStr == "" {
		return fallback
	}
	val, err := strconv.ParseInt(valStr, 10, 32)
	if err != nil {
		return fallback
	}
	return int32(val)
}

func getEnvFloat64(key string, fallback float64) float64 {
	valStr := getEnv(key, "")
	if valStr == "" {
		return fallback
	}
	val, err := strconv.ParseFloat(valStr, 64)
	if err != nil {
		return fallback
	}
	return val
}
