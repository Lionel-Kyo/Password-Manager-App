package main

import (
	"errors"
	"os"
	"path/filepath"
	"time"
)

func HandleSession(
	s *Session,
	db *Database,
	loginLimiter *LoginRateLimiter,
) {
	defer func() {
		s.Logout()
		s.conn.Close()
	}()

	for {
		req, err := s.ReadEncryptedRequest()
		if err != nil {
			return
		}

		resp := &ResponsePayload{
			Success: false,
		}

		switch req.Action {

		case "__BackupDatabase__":
			filename := time.Now().Format(
				"password_manager_backup_2006_01_02_15_04_05.db",
			)

			cwd, err := os.Getwd()
			if err != nil {
				resp.Error = "failed to get working directory: " + err.Error()
				break
			}

			fullPath, err := filepath.Abs(
				filepath.Join(cwd, filename),
			)
			if err != nil {
				resp.Error = "failed to resolve absolute path: " + err.Error()
				break
			}

			if err := db.BackupDatabase(fullPath); err != nil {
				resp.Error = "backup failed: " + err.Error()
				break
			}

			resp.Success = true

		case "Register":
			if req.Account == "" || req.Password == "" {
				resp.Error = "account and password required"
				break
			}

			if err := db.RegisterUser(
				req.Account,
				req.Password,
			); err != nil {
				resp.Error = "registration failed: " + err.Error()
				break
			}

			resp.Success = true

		case "Verify":
			if !loginLimiter.Allow(s.clientIP) {
				resp.Error = "too many login attempts; try again later"
				break
			}

			if req.Account == "" || req.Password == "" {
				loginLimiter.Failed(s.clientIP)
				resp.Error = "account and password required"
				break
			}

			id, key, ok := db.VerifyUser(
				req.Account,
				req.Password,
			)

			if !ok {
				loginLimiter.Failed(s.clientIP)
				resp.Error = "invalid credentials"
				break
			}

			copiedKey := make([]byte, len(key))
			copy(copiedKey, key)
			authToken, err := GlobalTokenStore.CreateToken(id, copiedKey)
			if err != nil {
				resp.Error = "failed to create auth token"
				break
			}

			loginLimiter.Success(s.clientIP)

			s.Authenticate(id, key)

			resp.AuthToken = authToken
			resp.Success = true

		case "VerifyToken":
			if !loginLimiter.Allow(s.clientIP) {
				resp.Error = "too many attempts; try again later"
				break
			}

			if req.AuthToken == "" {
				loginLimiter.Failed(s.clientIP)
				resp.Error = "auth token required"
				break
			}

			id, key, ok := GlobalTokenStore.ValidateToken(req.AuthToken)

			if !ok {
				loginLimiter.Failed(s.clientIP)
				resp.Error = UnauthorizedOrSessionExpiredErrorMsg
				break
			}

			loginLimiter.Success(s.clientIP)

			copiedKey := make([]byte, len(key))
			copy(copiedKey, key)
			s.Authenticate(id, copiedKey)

			resp.Success = true

		case "Logout":
			s.Logout()
			resp.Success = true

		case "ModifyPassword":
			if err := s.RequireAuthentication(); err != nil {
				resp.Error = err.Error()
				break
			}

			if req.OldPassword == "" ||
				req.NewPassword == "" {
				resp.Error = "old_password and new_password are required"
				break
			}

			userID, _, ok := s.GetUserCredentials()
			if !ok {
				resp.Error = UnauthorizedOrSessionExpiredErrorMsg
				break
			}

			newKey, err := db.ModifyPassword(
				userID,
				req.OldPassword,
				req.NewPassword,
			)
			if err != nil {
				resp.Error = err.Error()
				break
			}

			// Replace the old user encryption key.
			s.mu.Lock()

			for i := range s.userKey {
				s.userKey[i] = 0
			}

			s.userKey = newKey
			s.authenticatedAt = time.Now()
			s.lastActivityAt = time.Now()

			s.mu.Unlock()

			resp.Success = true

		case "GetItemNames":
			if err := s.RequireAuthentication(); err != nil {
				resp.Error = err.Error()
				break
			}

			userID, userKey, ok := s.GetUserCredentials()
			if !ok {
				resp.Error = UnauthorizedOrSessionExpiredErrorMsg
				break
			}

			names, err := db.GetItemNames(
				userID,
				userKey,
			)
			if err != nil {
				resp.Error = err.Error()
				break
			}

			resp.Success = true
			resp.ItemNames = names

		case "GetItem":
			if err := s.RequireAuthentication(); err != nil {
				resp.Error = err.Error()
				break
			}

			if req.ItemName == "" {
				resp.Error = "item_name is required"
				break
			}

			userID, userKey, ok := s.GetUserCredentials()
			if !ok {
				resp.Error = UnauthorizedOrSessionExpiredErrorMsg
				break
			}

			kvs, err := db.GetItem(
				userID,
				req.ItemName,
				userKey,
			)
			if err != nil {
				resp.Error = err.Error()
				break
			}

			resp.Success = true
			resp.KeyValues = kvs

		case "InsertItem":
			if err := s.RequireAuthentication(); err != nil {
				resp.Error = err.Error()
				break
			}

			if req.ItemName == "" {
				resp.Error = "item_name is required"
				break
			}

			userID, userKey, ok := s.GetUserCredentials()
			if !ok {
				resp.Error = UnauthorizedOrSessionExpiredErrorMsg
				break
			}

			if err := db.InsertItem(
				userID,
				req.ItemName,
				req.KeyValues,
				userKey,
			); err != nil {
				resp.Error = err.Error()
				break
			}

			resp.Success = true

		case "UpdateItem":
			if err := s.RequireAuthentication(); err != nil {
				resp.Error = err.Error()
				break
			}

			if req.ItemName == "" {
				resp.Error = "item_name is required"
				break
			}

			userID, userKey, ok := s.GetUserCredentials()
			if !ok {
				resp.Error = UnauthorizedOrSessionExpiredErrorMsg
				break
			}

			if err := db.UpdateItem(
				userID,
				req.ItemName,
				req.KeyValues,
				userKey,
			); err != nil {
				resp.Error = err.Error()
				break
			}

			resp.Success = true

		case "UpdateItemOrder":
			if err := s.RequireAuthentication(); err != nil {
				resp.Error = err.Error()
				break
			}

			userID, userKey, ok := s.GetUserCredentials()
			if !ok {
				resp.Error = UnauthorizedOrSessionExpiredErrorMsg
				break
			}

			if err := db.UpdateItemOrder(
				userID,
				req.OrderedItemNames,
				userKey,
			); err != nil {
				resp.Error = err.Error()
				break
			}

			resp.Success = true

		case "RemoveItem":
			if err := s.RequireAuthentication(); err != nil {
				resp.Error = err.Error()
				break
			}

			if req.ItemName == "" {
				resp.Error = "item_name is required"
				break
			}

			userID, userKey, ok := s.GetUserCredentials()
			if !ok {
				resp.Error = UnauthorizedOrSessionExpiredErrorMsg
				break
			}

			if err := db.RemoveItem(
				userID,
				req.ItemName,
				userKey,
			); err != nil {
				resp.Error = err.Error()
				break
			}

			resp.Success = true

		default:
			resp.Error = "unknown action"
		}

		if err := s.WriteEncryptedResponse(resp); err != nil {
			return
		}
	}
}

// Keep errors imported if additional handlers are added in the future.
var _ = errors.New
