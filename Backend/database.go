package main

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"time"

	orderedmap "github.com/wk8/go-ordered-map/v2"
	_ "modernc.org/sqlite"
)

type Database struct {
	db *sql.DB
}

type DecryptedItem struct {
	Name        string
	KeyValues   *orderedmap.OrderedMap[string, string]
	CreateAtUTC string
	UpdateAtUTC string
}

func InitDB(dbPath string) (*Database, error) {
	db, err := sql.Open("sqlite", dbPath+"?_journal_mode=WAL")
	if err != nil {
		return nil, err
	}

	schema := `
	CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		account TEXT UNIQUE NOT NULL,
		auth_hash TEXT NOT NULL,
		salt_auth TEXT NOT NULL,
		salt_data TEXT NOT NULL,
		create_at_utc TEXT NOT NULL,
		update_at_utc TEXT NOT NULL
	);

	CREATE TABLE IF NOT EXISTS items (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id INTEGER NOT NULL,
		display_index INTEGER NOT NULL DEFAULT 0,
		name_payload TEXT NOT NULL,
		map_payload TEXT NOT NULL,
		create_at_utc TEXT NOT NULL,
		update_at_utc TEXT NOT NULL,
		FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
	);
	`

	if _, err := db.Exec(schema); err != nil {
		return nil, err
	}

	return &Database{db: db}, nil
}

func (d *Database) BackupDatabase(backupPath string) error {
	_, err := d.db.Exec("VACUUM INTO ?;", backupPath)
	return err
}

func (d *Database) RegisterUser(account, password string) error {
	saltAuth, err := GenerateRandomBytes(SaltLen)
	if err != nil {
		return err
	}

	saltData, err := GenerateRandomBytes(SaltLen)
	if err != nil {
		return err
	}

	authHash := DeriveKey(password, saltAuth)
	now := time.Now().UTC().Format(time.RFC3339)

	_, err = d.db.Exec(
		"INSERT INTO users (account, auth_hash, salt_auth, salt_data, create_at_utc, update_at_utc) VALUES (?, ?, ?, ?, ?, ?)",
		account,
		base64.StdEncoding.EncodeToString(authHash),
		base64.StdEncoding.EncodeToString(saltAuth),
		base64.StdEncoding.EncodeToString(saltData),
		now,
		now,
	)
	return err
}

func (d *Database) VerifyUser(account, password string) (int64, []byte, bool) {
	var id int64
	var authHashB64, saltAuthB64, saltDataB64 string

	err := d.db.QueryRow("SELECT id, auth_hash, salt_auth, salt_data FROM users WHERE account = ?", account).
		Scan(&id, &authHashB64, &saltAuthB64, &saltDataB64)
	if err != nil {
		return 0, nil, false
	}

	storedAuthHash, _ := base64.StdEncoding.DecodeString(authHashB64)
	saltAuth, _ := base64.StdEncoding.DecodeString(saltAuthB64)
	saltData, _ := base64.StdEncoding.DecodeString(saltDataB64)

	computedAuthHash := DeriveKey(password, saltAuth)
	if !VerifyHash(computedAuthHash, storedAuthHash) {
		return 0, nil, false
	}

	userKey := DeriveKey(password, saltData)
	return id, userKey, true
}

func (d *Database) GetItemNames(userID int64, userKey []byte) ([]string, error) {
	rows, err := d.db.Query("SELECT name_payload FROM items WHERE user_id = ? ORDER BY display_index ASC", userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var names []string
	for rows.Next() {
		var namePayload string
		if err := rows.Scan(&namePayload); err != nil {
			return nil, err
		}
		decNameBytes, err := DecryptAESGCM(userKey, namePayload)
		if err != nil {
			continue
		}
		names = append(names, string(decNameBytes))
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return names, nil
}

func (d *Database) GetItem(userID int64, name string, userKey []byte) (*orderedmap.OrderedMap[string, string], error) {
	rows, err := d.db.Query("SELECT name_payload, map_payload FROM items WHERE user_id = ?", userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var namePayload, mapPayload string
		if err := rows.Scan(&namePayload, &mapPayload); err != nil {
			return nil, err
		}

		decNameBytes, err := DecryptAESGCM(userKey, namePayload)
		if err != nil {
			continue
		}

		if string(decNameBytes) == name {
			decMapBytes, err := DecryptAESGCM(userKey, mapPayload)
			if err != nil {
				return nil, err
			}

			kvs := orderedmap.New[string, string]()
			if err := json.Unmarshal(decMapBytes, &kvs); err != nil {
				return nil, err
			}
			return kvs, nil
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return nil, errors.New("item not found")
}

func (d *Database) InsertItem(userID int64, name string, keyValues *orderedmap.OrderedMap[string, string], userKey []byte) error {
	namePayload, err := EncryptAESGCM(userKey, []byte(name))
	if err != nil {
		return err
	}

	mapBytes, err := json.Marshal(keyValues)
	if err != nil {
		return err
	}

	mapPayload, err := EncryptAESGCM(userKey, mapBytes)
	if err != nil {
		return err
	}

	var maxIndex sql.NullInt64
	err = d.db.QueryRow("SELECT MAX(display_index) FROM items WHERE user_id = ?", userID).Scan(&maxIndex)
	if err != nil && err != sql.ErrNoRows {
		return err
	}

	nextDisplayIndex := int64(0)
	if maxIndex.Valid {
		nextDisplayIndex = maxIndex.Int64 + 1
	}

	now := time.Now().UTC().Format(time.RFC3339)

	_, err = d.db.Exec(
		"INSERT INTO items (user_id, display_index, name_payload, map_payload, create_at_utc, update_at_utc) VALUES (?, ?, ?, ?, ?, ?)",
		userID, nextDisplayIndex, namePayload, mapPayload, now, now,
	)
	return err
}

func (d *Database) UpdateItem(userID int64, name string, keyValues *orderedmap.OrderedMap[string, string], userKey []byte) error {
	rows, err := d.db.Query("SELECT id, name_payload FROM items WHERE user_id = ?", userID)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var id int64
		var namePayload string
		if err := rows.Scan(&id, &namePayload); err != nil {
			continue
		}

		decNameBytes, err := DecryptAESGCM(userKey, namePayload)
		if err != nil {
			continue
		}

		if string(decNameBytes) == name {
			rows.Close()

			newNamePayload, err := EncryptAESGCM(userKey, []byte(name))
			if err != nil {
				return err
			}

			newMapPayloadBytes, err := json.Marshal(keyValues)
			if err != nil {
				return err
			}

			newMapPayload, err := EncryptAESGCM(userKey, newMapPayloadBytes)
			if err != nil {
				return err
			}

			now := time.Now().UTC().Format(time.RFC3339)

			_, err = d.db.Exec(
				"UPDATE items SET name_payload = ?, map_payload = ?, update_at_utc = ? WHERE id = ?",
				newNamePayload, newMapPayload, now, id,
			)
			return err
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	return errors.New("item not found")
}

func (d *Database) UpdateItemOrder(userID int64, orderedNames []string, userKey []byte) error {
	rows, err := d.db.Query("SELECT id, name_payload FROM items WHERE user_id = ?", userID)
	if err != nil {
		return err
	}

	nameToID := make(map[string]int64)
	for rows.Next() {
		var id int64
		var namePayload string
		if err := rows.Scan(&id, &namePayload); err != nil {
			rows.Close()
			return err
		}

		decName, err := DecryptAESGCM(userKey, namePayload)
		if err != nil {
			continue
		}
		nameToID[string(decName)] = id
	}
	rows.Close()

	tx, err := d.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare("UPDATE items SET display_index = ?, update_at_utc = ? WHERE id = ? AND user_id = ?")
	if err != nil {
		return err
	}
	defer stmt.Close()

	now := time.Now().UTC().Format(time.RFC3339)

	for idx, name := range orderedNames {
		if id, ok := nameToID[name]; ok {
			if _, err := stmt.Exec(idx, now, id, userID); err != nil {
				return err
			}
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	return tx.Commit()
}

func (d *Database) RemoveItem(userID int64, name string, userKey []byte) error {
	rows, err := d.db.Query("SELECT id, name_payload FROM items WHERE user_id = ?", userID)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var id int64
		var namePayload string
		if err := rows.Scan(&id, &namePayload); err != nil {
			continue
		}

		decName, err := DecryptAESGCM(userKey, namePayload)
		if err != nil {
			continue
		}

		if string(decName) == name {
			rows.Close()
			_, err := d.db.Exec("DELETE FROM items WHERE id = ?", id)
			return err
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	return errors.New("item not found")
}

func (d *Database) ModifyPassword(userID int64, oldPassword, newPassword string) ([]byte, error) {
	var authHashB64, saltAuthB64, saltDataB64 string
	err := d.db.QueryRow("SELECT auth_hash, salt_auth, salt_data FROM users WHERE id = ?", userID).
		Scan(&authHashB64, &saltAuthB64, &saltDataB64)
	if err != nil {
		return nil, errors.New("user not found")
	}

	storedAuthHash, _ := base64.StdEncoding.DecodeString(authHashB64)
	oldSaltAuth, _ := base64.StdEncoding.DecodeString(saltAuthB64)
	oldSaltData, _ := base64.StdEncoding.DecodeString(saltDataB64)

	// Verify old password
	computedAuthHash := DeriveKey(oldPassword, oldSaltAuth)
	if !VerifyHash(computedAuthHash, storedAuthHash) {
		return nil, errors.New("invalid original password")
	}

	oldUserKey := DeriveKey(oldPassword, oldSaltData)

	// Fetch and decrypt all existing items with oldUserKey
	rows, err := d.db.Query("SELECT name_payload, map_payload, create_at_utc, update_at_utc FROM items WHERE user_id = ? ORDER BY display_index ASC", userID)
	if err != nil {
		return nil, err
	}

	var decryptedItems []DecryptedItem
	for rows.Next() {
		var namePayload, mapPayload, createAt, updateAt string
		if err := rows.Scan(&namePayload, &mapPayload, &createAt, &updateAt); err != nil {
			rows.Close()
			return nil, err
		}

		decNameBytes, err := DecryptAESGCM(oldUserKey, namePayload)
		if err != nil {
			rows.Close()
			return nil, errors.New("failed decrypting item during re-key")
		}

		decMapBytes, err := DecryptAESGCM(oldUserKey, mapPayload)
		if err != nil {
			rows.Close()
			return nil, errors.New("failed decrypting payload during re-key")
		}

		kvs := orderedmap.New[string, string]()
		if err := json.Unmarshal(decMapBytes, &kvs); err != nil {
			rows.Close()
			return nil, err
		}

		decryptedItems = append(decryptedItems, DecryptedItem{
			Name:        string(decNameBytes),
			KeyValues:   kvs,
			CreateAtUTC: createAt,
			UpdateAtUTC: updateAt,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()

	// Generate new salts and keys
	newSaltAuth, err := GenerateRandomBytes(SaltLen)
	if err != nil {
		return nil, err
	}

	newSaltData, err := GenerateRandomBytes(SaltLen)
	if err != nil {
		return nil, err
	}

	newAuthHash := DeriveKey(newPassword, newSaltAuth)
	newUserKey := DeriveKey(newPassword, newSaltData)
	now := time.Now().UTC().Format(time.RFC3339)

	// Begin Atomic Transaction
	tx, err := d.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Update user record
	_, err = tx.Exec("UPDATE users SET auth_hash = ?, salt_auth = ?, salt_data = ?, update_at_utc = ? WHERE id = ?",
		base64.StdEncoding.EncodeToString(newAuthHash),
		base64.StdEncoding.EncodeToString(newSaltAuth),
		base64.StdEncoding.EncodeToString(newSaltData),
		now,
		userID,
	)
	if err != nil {
		return nil, err
	}

	// Delete old encrypted items
	if _, err := tx.Exec("DELETE FROM items WHERE user_id = ?", userID); err != nil {
		return nil, err
	}

	// Re-encrypt and insert items with newUserKey
	for item_index, item := range decryptedItems {
		namePayload, err := EncryptAESGCM(newUserKey, []byte(item.Name))
		if err != nil {
			return nil, err
		}

		mapPayloadBytes, _ := json.Marshal(item.KeyValues)
		mapPayload, err := EncryptAESGCM(newUserKey, mapPayloadBytes)
		if err != nil {
			return nil, err
		}

		_, err = tx.Exec(
			"INSERT INTO items (user_id, display_index, name_payload, map_payload, create_at_utc, update_at_utc) VALUES (?, ?, ?, ?, ?, ?)",
			userID, item_index, namePayload, mapPayload, item.CreateAtUTC, now,
		)
		if err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return newUserKey, nil
}
