package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"io"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/hkdf"
)

const (
	ArgonTime    = 3
	ArgonMemory  = 64 * 1024
	ArgonThreads = 4
	ArgonKeyLen  = 32
	SaltLen      = 16
)

func GenerateRandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	return b, nil
}

// DeriveKey derives a 32-byte key from password and salt using Argon2id.
func DeriveKey(password string, salt []byte) []byte {
	return argon2.IDKey([]byte(password), salt, ArgonTime, ArgonMemory, ArgonThreads, ArgonKeyLen)
}

func VerifyHash(computed, stored []byte) bool {
	return subtle.ConstantTimeCompare(computed, stored) == 1
}

func EncryptAESGCM(key []byte, plaintext []byte) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonce, err := GenerateRandomBytes(gcm.NonceSize())
	if err != nil {
		return "", err
	}

	ciphertext := gcm.Seal(nonce, nonce, plaintext, nil)

	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

func DecryptAESGCM(key []byte, combinedB64 string) ([]byte, error) {
	data, err := base64.StdEncoding.DecodeString(combinedB64)
	if err != nil {
		return nil, err
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}

	nonceSize := gcm.NonceSize()
	if len(data) < nonceSize {
		return nil, errors.New("ciphertext too short")
	}

	nonce := data[:nonceSize]
	ciphertext := data[nonceSize:]

	return gcm.Open(nil, nonce, ciphertext, nil)
}

func DeriveSessionKey(serverPrivateKey *ecdh.PrivateKey, clientPublicKeyBytes []byte) ([]byte, error) {
	clientPubKey, err := ecdh.X25519().NewPublicKey(clientPublicKeyBytes)
	if err != nil {
		return nil, err
	}

	sharedSecret, err := serverPrivateKey.ECDH(clientPubKey)
	if err != nil {
		return nil, err
	}

	hkdfReader := hkdf.New(sha256.New, sharedSecret, nil, []byte("websocket-ecc-aes-handshake"))
	sessionKey := make([]byte, 32)
	if _, err := io.ReadFull(hkdfReader, sessionKey); err != nil {
		return nil, err
	}

	return sessionKey, nil
}
