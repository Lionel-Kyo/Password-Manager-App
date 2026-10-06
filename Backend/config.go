package main

import (
	"os"
	"strconv"
	"strings"
)

type Config struct {
	IP                      string
	Port                    string
	ServerCertPEM           string
	ServerKeyPEM            string
	CorsProtocols           []string
	CorsOrigins             []string
	MaxWebSocketConnections int32
	SessionIdleTimeoutMins  float64
}

func LoadConfig() *Config {
	return &Config{
		IP:   getEnv("SERVER_IP", "0.0.0.0"),
		Port: getEnv("SERVER_PORT", "8080"),
		ServerCertPEM: getEnv("SERVER_CERT_PEM", ""),
		ServerKeyPEM: getEnv("SERVER_KEY_PEM", ""),
		CorsProtocols:           getEnvSlice("CORS_PROTOCOLS", "http;https;ws;wss", ";"),
		CorsOrigins:             getEnvSlice("CORS_ORIGINS", "localhost;127.0.0.1;192.168.11.19", ";"),
		MaxWebSocketConnections: getEnvInt32("MAX_WEB_SOCKET_CONNECTIONS", 100),
		SessionIdleTimeoutMins:  getEnvFloat64("SESSION_IDLE_TIMEOUT_MINS", 5.0),
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
