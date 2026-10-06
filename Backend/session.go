package main

import (
	"crypto"
	"crypto/ecdh"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	orderedmap "github.com/wk8/go-ordered-map/v2"
)

type ServerIdentity struct {
	CertPEM []byte
	Signer  crypto.Signer
}

func LoadServerPEM(certPEM, keyPEM string) (*ServerIdentity, error) {
	if certPEM == "" || keyPEM == "" {
		return nil, errors.New("SERVER_CERT_PEM and SERVER_KEY_PEM must be set in environment")
	}

	tlsCert, err := tls.X509KeyPair(
		[]byte(certPEM),
		[]byte(keyPEM),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to parse x509 key pair: %w", err)
	}

	signer, ok := tlsCert.PrivateKey.(crypto.Signer)
	if !ok {
		return nil, errors.New("private key does not implement crypto.Signer")
	}

	return &ServerIdentity{
		CertPEM: []byte(certPEM),
		Signer:  signer,
	}, nil
}

type Session struct {
	conn *websocket.Conn

	sessionKey []byte

	userID          int64
	userKey         []byte
	authenticatedAt time.Time
	lastActivityAt  time.Time

	idleTimeout time.Duration

	clientIP string

	mu sync.Mutex
}

type HandshakeReq struct {
	Action          string `json:"action"`
	ClientPublicKey string `json:"client_public_key"`
}

type HandshakeResp struct {
	Status          string `json:"status"`
	ServerPublicKey string `json:"server_public_key"`
	Certificate     string `json:"certificate"`
	Signature       string `json:"signature"`
}

type EncryptedEnvelope struct {
	Payload string `json:"payload"`
}

type RequestPayload struct {
	Action           string                                 `json:"action"`
	Account          string                                 `json:"account,omitempty"`
	Password         string                                 `json:"password,omitempty"`
	OldPassword      string                                 `json:"old_password,omitempty"`
	NewPassword      string                                 `json:"new_password,omitempty"`
	OrderedItemNames []string                               `json:"ordered_item_names,omitempty"`
	ItemName         string                                 `json:"item_name,omitempty"`
	KeyValues        *orderedmap.OrderedMap[string, string] `json:"key_values,omitempty"`
}

type ResponsePayload struct {
	Success   bool                                   `json:"success"`
	Error     string                                 `json:"error,omitempty"`
	ItemNames []string                               `json:"item_names,omitempty"`
	KeyValues *orderedmap.OrderedMap[string, string] `json:"key_values,omitempty"`
}

func ConfigureWebSocket(ws *websocket.Conn) {
	ws.SetReadLimit(MaxWebSocketMessageSize)

	_ = ws.SetReadDeadline(time.Now().Add(ReadTimeout))

	ws.SetPongHandler(func(string) error {
		return ws.SetReadDeadline(time.Now().Add(ReadTimeout))
	})
}

func PerformHandshake(
	ws *websocket.Conn,
	sessionIdleTimeoutMins float64,
	identity *ServerIdentity,
	clientIP string,
) (*Session, error) {
	ConfigureWebSocket(ws)

	if err := ws.SetReadDeadline(
		time.Now().Add(HandshakeTimeout),
	); err != nil {
		return nil, err
	}

	_, msg, err := ws.ReadMessage()
	if err != nil {
		return nil, err
	}

	var req HandshakeReq
	if err := json.Unmarshal(msg, &req); err != nil {
		return nil, errors.New("invalid handshake JSON")
	}

	if req.Action != "handshake" {
		return nil, errors.New("invalid handshake initiation")
	}

	clientPubKeyBytes, err := base64.StdEncoding.DecodeString(
		req.ClientPublicKey,
	)
	if err != nil {
		return nil, errors.New("invalid client public key")
	}

	if len(clientPubKeyBytes) != 32 {
		return nil, errors.New("invalid client public key length")
	}

	serverPrivKey, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf(
			"failed to generate server key: %w",
			err,
		)
	}

	serverPubKeyBytes := serverPrivKey.PublicKey().Bytes()

	sessionKey, err := DeriveSessionKey(
		serverPrivKey,
		clientPubKeyBytes,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to derive session key: %w", err)
	}

	signedData := make([]byte, 0, len(serverPubKeyBytes)+len(clientPubKeyBytes))

	signedData = append(signedData, serverPubKeyBytes...)
	signedData = append(signedData, clientPubKeyBytes...)

	hashed := sha256.Sum256(signedData)

	signature, err := identity.Signer.Sign(rand.Reader, hashed[:], crypto.SHA256)
	if err != nil {
		return nil, fmt.Errorf("failed to sign handshake: %w", err)
	}

	resp := HandshakeResp{
		Status:          "ok",
		ServerPublicKey: base64.StdEncoding.EncodeToString(serverPubKeyBytes),
		Certificate:     base64.StdEncoding.EncodeToString(identity.CertPEM),
		Signature:       base64.StdEncoding.EncodeToString(signature),
	}

	respBytes, err := json.Marshal(resp)
	if err != nil {
		return nil, err
	}

	if err := ws.SetWriteDeadline(
		time.Now().Add(WriteTimeout),
	); err != nil {
		return nil, err
	}

	if err := ws.WriteMessage(
		websocket.TextMessage,
		respBytes,
	); err != nil {
		return nil, err
	}

	session := &Session{
		conn:        ws,
		sessionKey:  sessionKey,
		idleTimeout: time.Duration(sessionIdleTimeoutMins) * time.Minute,
		clientIP:    clientIP,
	}

	session.Touch()

	if err := ws.SetReadDeadline(
		time.Now().Add(ReadTimeout),
	); err != nil {
		return nil, err
	}

	return session, nil
}

func (s *Session) Touch() {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.lastActivityAt = time.Now()
}

func (s *Session) Authenticate(
	userID int64,
	userKey []byte,
) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.userID = userID
	s.userKey = userKey
	s.authenticatedAt = time.Now()
	s.lastActivityAt = time.Now()
}

func (s *Session) Logout() {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.userID = 0

	for i := range s.userKey {
		s.userKey[i] = 0
	}

	s.userKey = nil

	s.authenticatedAt = time.Time{}
	s.lastActivityAt = time.Time{}
}

func (s *Session) IsSessionValid() bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.userID == 0 || len(s.userKey) == 0 {
		return false
	}

	now := time.Now()

	if s.idleTimeout > 0 &&
		!s.lastActivityAt.IsZero() &&
		now.Sub(s.lastActivityAt) > s.idleTimeout {
		return false
	}

	return true
}

func (s *Session) RequireAuthentication() error {
	if !s.IsSessionValid() {
		s.Logout()
		return errors.New("unauthorized or session expired")
	}

	return nil
}

func (s *Session) GetUserCredentials() (int64, []byte, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.userID == 0 || len(s.userKey) == 0 {
		return 0, nil, false
	}

	return s.userID, s.userKey, true
}

func (s *Session) ReadEncryptedRequest() (*RequestPayload, error) {
	if err := s.conn.SetReadDeadline(time.Now().Add(ReadTimeout)); err != nil {
		return nil, err
	}

	messageType, msg, err := s.conn.ReadMessage()
	if err != nil {
		return nil, err
	}

	if messageType != websocket.TextMessage {
		return nil, errors.New("invalid websocket message type")
	}

	var env EncryptedEnvelope
	if err := json.Unmarshal(msg, &env); err != nil {
		return nil, errors.New("invalid encrypted envelope")
	}

	if env.Payload == "" {
		return nil, errors.New("encrypted payload is empty")
	}

	decryptedBytes, err := DecryptAESGCM(
		s.sessionKey,
		env.Payload,
	)
	if err != nil {
		return nil, errors.New("failed to decrypt message: " + err.Error())
	}

	var req RequestPayload
	if err := json.Unmarshal(
		decryptedBytes,
		&req,
	); err != nil {
		return nil, errors.New("invalid request payload")
	}

	s.Touch()

	return &req, nil
}

func (s *Session) WriteEncryptedResponse(
	resp *ResponsePayload,
) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	rawBytes, err := json.Marshal(resp)
	if err != nil {
		return err
	}

	encryptedB64, err := EncryptAESGCM(s.sessionKey, rawBytes)
	if err != nil {
		return err
	}

	env := EncryptedEnvelope{
		Payload: encryptedB64,
	}

	envBytes, err := json.Marshal(env)
	if err != nil {
		return err
	}

	if len(envBytes) > MaxWebSocketMessageSize {
		return errors.New("encrypted response exceeds websocket message limit")
	}

	if err := s.conn.SetWriteDeadline(
		time.Now().Add(WriteTimeout),
	); err != nil {
		return err
	}

	return s.conn.WriteMessage(
		websocket.TextMessage,
		envBytes,
	)
}
