package main

import (
	"crypto/rand"
	"encoding/base64"
	"sync"
	"time"
)

type TokenRecord struct {
	UserID    int64
	UserKey   []byte
	ExpiresAt time.Time
}

type TokenStore struct {
	sync.Mutex
	tokens          map[string]TokenRecord
	lifeTime        time.Duration
	cleanupInterval time.Duration
}

var GlobalTokenStore = &TokenStore{}

func (ts *TokenStore) Init(storeTime time.Duration, cleanupInterval time.Duration) {
	ts.Lock()
	defer ts.Unlock()

	ts.tokens = make(map[string]TokenRecord)
	ts.lifeTime = storeTime
	ts.cleanupInterval = cleanupInterval

	go ts.startCleanupWorker(cleanupInterval)
}

func generateSecureToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.URLEncoding.EncodeToString(b), nil
}

func (ts *TokenStore) CreateToken(userID int64, userKey []byte) (string, error) {
	token, err := generateSecureToken()
	if err != nil {
		return "", err
	}

	ts.Lock()
	defer ts.Unlock()

	ts.tokens[token] = TokenRecord{
		UserID:    userID,
		UserKey:   userKey,
		ExpiresAt: time.Now().Add(ts.lifeTime),
	}

	return token, nil
}

func (ts *TokenStore) ValidateToken(token string) (int64, []byte, bool) {
	ts.Lock()
	defer ts.Unlock()

	record, exists := ts.tokens[token]
	if !exists {
		return 0, nil, false
	}

	if time.Now().After(record.ExpiresAt) {
		ts.revokeTokenLockRequired(token)
		return 0, nil, false
	}

	record.ExpiresAt = time.Now().Add(ts.lifeTime)

	return record.UserID, record.UserKey, true
}

func (ts *TokenStore) revokeTokenLockRequired(token string) {
	record, exists := ts.tokens[token]
	if !exists {
		return
	}

	for i := range record.UserKey {
		record.UserKey[i] = 0
	}

	delete(ts.tokens, token)
}

func (ts *TokenStore) RevokeToken(token string) {
	ts.Lock()
	defer ts.Unlock()
	ts.revokeTokenLockRequired(token)
}

func (ts *TokenStore) startCleanupWorker(interval time.Duration) {
	if interval <= 0 {
		return
	}

	ticker := time.NewTicker(interval)
	for range ticker.C {
		ts.Lock()
		now := time.Now()
		for token, record := range ts.tokens {
			if now.After(record.ExpiresAt) {
				ts.revokeTokenLockRequired(token)
			}
		}
		ts.Unlock()
	}
}
