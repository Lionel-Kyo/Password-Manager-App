 # Password Manager

 A cross-platform password manager built with **Go** as the backend and **Flutter** as the frontend.

 The Go backend can serve the Flutter Web application directly. Flutter applications running on platforms such as Android and Windows can also connect to the same backend remotely.

 All client-server communication uses **WebSocket** with an additional application-level encryption layer.

 > **Status:** Personal project stage. This project should undergo additional security review before being used as a production password manager.

 ## Features

- Cross-platform Flutter frontend
- Web
- Android
- Windows
- Other Flutter-supported platforms
- Go backend
- Go backend can serve the Flutter Web application
- Native Flutter applications can connect to the backend
- WebSocket-only client-server communication
- X25519 key agreement for session keys
- HKDF-SHA256 session-key derivation
- AES-256-GCM message encryption
- Argon2id password-based key derivation
- Separate password-derived keys for authentication and user data
- Encrypted password-manager item names
- Encrypted password-manager key/value data
- Password change with automatic data re-encryption
- SQLite database
- SQLite WAL mode
- Database backup support
- Configurable session expiration
- Login rate limiting
- WebSocket message-size limits
- WebSocket read/write deadlines
- Concurrent connection limits
- Explicit logout support

 ## Architecture

```
                    +-------------------------+
                    |       Flutter Web       |
                    |                         |
                    |  Served by Go Backend   |
                    +------------+------------+
                                 |
                                 | WebSocket
                                 |
+-----------------+              v
| Flutter Native  |      +---------------------+
| Android/Windows |----->|     Go Backend      |
| etc.            |  WS  |                     |
+-----------------+      |  WebSocket Server   |
                         |  Session Management |
                         |  Authentication     |
                         |  Password Manager   |
                         +----------+----------+
                                    |
                                    |
                             +------+------+
                             |   SQLite    |
                             |  Database   |
                             +-------------+
```

 The backend has two main responsibilities:

1. Serve the Flutter Web application.
2. Provide the password-manager API over WebSocket.

 Native Flutter applications can connect directly to the backend WebSocket endpoint.

 ## Communication Protocol

 The application uses **WebSocket as the only client-server communication channel**.

 After establishing a WebSocket connection, the client performs a cryptographic handshake.

 The protocol has two main phases:

1. Session key establishment.
2. Encrypted application messages.

 ## Cryptographic Design

 The project uses the following cryptographic primitives:

| Purpose | Algorithm |
| --- | --- |
| Session key agreement | X25519 |
| Session key derivation | HKDF-SHA256 |
| Message encryption | AES-256-GCM |
| Password key derivation | Argon2id |
| Hash comparison | Constant-time comparison |
| Randomness | `crypto/rand` |

### Argon2id Parameters

 The current Argon2id configuration is:

| Parameter | Value |
| --- | --- |
| Time | 3 |
| Memory | 64 MiB |
| Threads | 4 |
| Key length | 32 bytes |
| Salt length | 16 bytes |

The application derives 32-byte cryptographic keys.

 ## Handshake

 The client starts the connection by sending a handshake request:

```
{
  "action": "handshake",
  "client_public_key": "<base64 X25519 public key>"
}
```

 The client public key is a 32-byte X25519 public key encoded using Base64.

 The server generates a temporary X25519 key pair for the session.

 The server derives a shared secret:

```
Client X25519 Public Key
          +
Server X25519 Private Key
          |
          v
      ECDH Shared Secret
```

 The shared secret is then passed through HKDF-SHA256:

```
HKDF-SHA256(
    sharedSecret,
    salt = nil,
    info = "websocket-ecc-aes-handshake"
)
```

 The first 32 bytes of the HKDF output are used as the session key.

 Conceptually:

```
Client Private Key
        |
        |
        +-------------------+
        |                   |
        v                   v
Client Public          Server Public
                            |
                            |
                      Server Private
                            |
                            v
                       X25519 ECDH
                            |
                            v
                      Shared Secret
                            |
                            v
                      HKDF-SHA256
                            |
                            v
                    32-byte Session Key
```

 ## Server Authentication

 The server also has a long-term certificate and signing key.

 They are loaded from:

```
SERVER_CERT_PEM
SERVER_KEY_PEM
```

 During the handshake, the server returns:

```
{
  "status": "ok",
  "server_public_key": "<base64 X25519 public key>",
  "certificate": "<base64 server certificate>",
  "signature": "<base64 signature>"
}
```

 The signature is calculated over:

```
SHA-256(ServerPublicKey || ClientPublicKey)
```

 This binds the server's ephemeral X25519 public key to the client public key used for the current handshake.

 The certificate is provided to the client so that the client can verify the server's long-term identity.

 ### Client-side Verification

 The client should verify all of the following before trusting the session key:

1. The server certificate.
2. The server certificate's trust relationship or configured certificate pin.
3. The server signature.
4. That the signature covers the exact client and server ephemeral public keys used for this handshake.
5. The certificate is currently valid.

 The client must not blindly trust the certificate or signature without verification.

 ## Encrypted Messages

 After the handshake, application messages are encrypted using AES-256-GCM with the derived session key.

 The encrypted message has the following structure:

```
{
  "payload": "<base64 ciphertext>"
}
```

 The plaintext request is serialized as JSON before encryption.

 For example:

```
{
  "action": "GetItem",
  "item_name": "GitHub"
}
```

 is encrypted into the `payload` field.

 Responses use the same mechanism.

 For example:

```
{
  "success": true,
  "key_values": {
    "account": "alice",
    "password": "example-password"
  }
}
```

 is encrypted before being sent to the client.

 ## AES-GCM Format

 The application uses Go's `cipher.NewGCM`.

 For every encrypted message, a new random GCM nonce is generated using `crypto/rand`.

 The binary format is:

```
nonce || ciphertext || authentication tag
```

 This combined value is then Base64-encoded.

 Conceptually:

```
Plaintext
   |
   v
AES-256-GCM
   |
   +-- Random nonce
   |
   +-- Ciphertext + authentication tag
              |
              v
        Base64 encoding
              |
              v
        "payload" field
```

 A fresh random nonce is generated for every encryption operation.

 ## Password-Based Key Derivation

 User passwords are never stored directly.

 The project uses **Argon2id** to derive cryptographic keys from passwords.

```
Argon2id(
    password,
    salt,
    time = 3,
    memory = 64 MiB,
    threads = 4,
    keyLength = 32
)
```

 A random 16-byte salt is generated for each purpose.

 Two separate salts are used:

```
salt_auth
salt_data
```

 This results in two independent password-derived keys.

 ## Authentication Key

 During registration, the server generates:

```
salt_auth
```

 It then derives:

```
authHash = Argon2id(password, salt_auth)
```

 The following information is stored in the database:

```
auth_hash
salt_auth
```

 The plaintext password is not stored.

 During login, the server derives the key again:

```
computedAuthHash = Argon2id(password, salt_auth)
```

 The computed value is compared with the stored value using a constant-time comparison.

 ## User Data Encryption Key

 A separate random salt is generated:

```
salt_data
```

 The user's data encryption key is derived using:

```
userKey = Argon2id(password, salt_data)
```

 The resulting 32-byte key is used to encrypt password-manager items.

 The database stores:

```
salt_data
```

 but does not store the plaintext user encryption key.

 ## Data Encryption

 Password-manager item names and key/value data are encrypted with the user's data encryption key.

 For example, an item such as:

```
{
  "name": "GitHub",
  "key_values": {
    "account": "alice",
    "password": "my-password"
  }
}
```

 is stored approximately as:

```
name_payload = AES-256-GCM(userKey, "GitHub")

map_payload =
    AES-256-GCM(
        userKey,
        {
            "account": "alice",
            "password": "my-password"
        }
    )
```

 Therefore, the plaintext item name and key/value data are not stored directly in SQLite.

 ## Database

 The backend uses **SQLite** with WAL mode enabled.

 The database contains two primary tables:

```
users
items
```

 ### Users

```
users
├── id
├── account
├── auth_hash
├── salt_auth
├── salt_data
├── create_at_utc
└── update_at_utc
```

 ### Items

```
items
├── id
├── user_id
├── display_index
├── name_payload
├── map_payload
├── create_at_utc
└── update_at_utc
```

 Items belong to users through:

```
items.user_id -> users.id
```

 ## Database Encryption Scope

 The project uses **field-level encryption** for sensitive password-manager data.

 The following item data is encrypted:

- Item name
- Item key/value data

 However, some database metadata remains unencrypted, including:

- Account name
- User ID
- Item database ID
- Display order
- Creation timestamp
- Update timestamp

 Therefore, this project does **not** provide full-database encryption.

 For example, someone with access to the SQLite database may still be able to see:

```
account
item count
item ordering
timestamps
database structure
```

 but should not be able to directly read the encrypted item names or values without the user's data encryption key.

 ## Password Change

 Changing a password requires re-encrypting all existing password-manager items.

 The process is:

```
                 Old Password
                      |
                      v
             Verify Old Password
                      |
                      v
             Derive Old User Key
                      |
                      v
              Decrypt All Items
                      |
                      v
              Generate New Salts
                      |
                      v
                 New Password
                      |
             +--------+--------+
             |                 |
             v                 v
       New Auth Key       New User Key
                               |
                               v
                       Encrypt All Items
                               |
                               v
                         SQLite Update
```

 The operation is performed inside a SQLite transaction.

 If an error occurs during the transaction, the changes are rolled back.

 Existing item creation timestamps are preserved.

 The update timestamp is changed.

 ## Session Management

 A WebSocket session initially has no authenticated user.

 After a successful `Verify` request, the session stores:

```
userID
userKey
authenticatedAt
```

 Protected operations require a valid authenticated session.

 The session is considered invalid when:

- No user has authenticated.
- The configured session expiration time has passed.
- The client explicitly logs out.
- The WebSocket connection is closed.

 Session expiration is controlled by the configured session expiration value.

 After a successful password change, the session's authentication timestamp is reset and the new user data encryption key replaces the old key.

 ### Logout

 Logout should invalidate the authenticated state of the current WebSocket session.

 A logout operation should:

- Clear the authenticated user ID.
- Clear the user data encryption key.
- Reset the authentication timestamp.
- Prevent subsequent authenticated operations on the same session.

 Closing the WebSocket connection also terminates the session.

 ## Rate Limiting

 Authentication attempts are rate-limited to reduce the effectiveness of online password-guessing attacks.

 Rate limiting should be applied to authentication-related operations, particularly:

- `Verify`
- `Register`
- Password-changing operations where appropriate

 The exact rate-limit policy is configuration-dependent.

 Rate limiting is an additional protection and does not replace a strong password or Argon2id.

 ## WebSocket Security Limits

 The server applies limits to WebSocket connections to reduce resource exhaustion and denial-of-service risks.

 These protections include:

- Maximum WebSocket message size.
- Read deadlines.
- Write deadlines.
- Connection limits.
- Controlled connection cleanup.
- Handshake timeouts.

 Clients should also apply reasonable operation timeouts when waiting for responses.

 ## Connection Limits

 The backend can limit the number of simultaneous WebSocket connections.

 When the configured connection limit has been reached, new connections should be rejected rather than allowing unbounded resource consumption.

 This protects the server against excessive concurrent connections.

 ## API

 All API requests are sent through the encrypted WebSocket protocol.

 ### Request

 The general request structure is:

```
{
  "action": "..."
}
```

 Additional fields depend on the requested action.

 ### Response

 The general response structure is:

```
{
  "success": true,
  "error": "",
  "item_names": [],
  "key_values": {}
}
```

 ## API Actions

 ### Register

 Creates a new user account.

 Request:

```
{
  "action": "Register",
  "account": "alice",
  "password": "..."
}
```

 Authentication is not required.

 ### Verify

 Authenticates an existing user.

 Request:

```
{
  "action": "Verify",
  "account": "alice",
  "password": "..."
}
```

 On success, the server associates the WebSocket session with the authenticated user.

 ### Logout

 Logs out the current WebSocket session.

 Request:

```
{
  "action": "Logout"
}
```

 After logout, protected operations require authentication again.

 The server should clear the session's authentication state and user data encryption key.

 ### GetItemNames

 Returns the user's item names in display order.

 Request:

```
{
  "action": "GetItemNames"
}
```

 Response:

```
{
  "success": true,
  "item_names": [
    "GitHub",
    "Google",
    "AWS"
  ]
}
```

 Requires authentication.

 ### GetItem

 Gets the key/value data of an item.

 Request:

```
{
  "action": "GetItem",
  "item_name": "GitHub"
}
```

 Response:

```
{
  "success": true,
  "key_values": {
    "username": "alice",
    "password": "..."
  }
}
```

 Requires authentication.

 ### InsertItem

 Creates a new password-manager item.

 Request:

```
{
  "action": "InsertItem",
  "item_name": "GitHub",
  "key_values": {
    "username": "alice",
    "password": "..."
  }
}
```

 Requires authentication.

 ### UpdateItem

 Updates an existing item.

 Request:

```
{
  "action": "UpdateItem",
  "item_name": "GitHub",
  "key_values": {
    "username": "alice",
    "password": "new-password"
  }
}
```

 Requires authentication.

 ### UpdateItemOrder

 Updates the display order of items.

 Request:

```
{
  "action": "UpdateItemOrder",
  "ordered_item_names": [
    "GitHub",
    "AWS",
    "Google"
  ]
}
```

 Requires authentication.

 ### RemoveItem

 Deletes an item.

 Request:

```
{
  "action": "RemoveItem",
  "item_name": "GitHub"
}
```

 Requires authentication.

 ### ModifyPassword

 Changes the user's password and re-encrypts all existing items.

 Request:

```
{
  "action": "ModifyPassword",
  "old_password": "...",
  "new_password": "..."
}
```

 Requires authentication.

 ### BackupDatabase

 Creates a SQLite database backup using:

```
VACUUM INTO ...
```

 The generated filename follows this pattern:

```
password_manager_backup_YYYY_MM_DD_HH_MM_SS.db
```

 The backup contains encrypted item payloads but also contains unencrypted database metadata.

 Backup files should therefore be protected like other sensitive password-manager data.

 ## Configuration

 The backend requires a server certificate and private signing key.

 Environment variables:

```
SERVER_CERT_PEM
SERVER_KEY_PEM
```

 Example:

```
export SERVER_CERT_PEM="-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----"

export SERVER_KEY_PEM="-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----"
```

 Never commit a server private key to source control.

 Other server configuration should include appropriate values for:

- Server bind address.
- Server port.
- Session expiration.
- WebSocket maximum message size.
- WebSocket read timeout.
- WebSocket write timeout.
- WebSocket handshake timeout.
- Maximum concurrent connections.
- Authentication rate limits.

 ## Security Model

 The security architecture can be summarized as:

```
+----------------------------------------------+
|              Flutter Client                  |
+----------------------+-----------------------+
                       |
                       | WebSocket
                       v
+----------------------------------------------+
|        Application Message Encryption        |
|                AES-256-GCM                   |
+----------------------+-----------------------+
                       |
                       v
+----------------------------------------------+
|             Session Key Agreement            |
|                   X25519                     |
+----------------------+-----------------------+
                       |
                       v
+----------------------------------------------+
|             Session Key Derivation           |
|                HKDF-SHA256                   |
+----------------------+-----------------------+
                       |
                       v
+----------------------------------------------+
|             Server Authentication            |
|          Certificate + Signature             |
+----------------------+-----------------------+
                       |
                       v
+----------------------------------------------+
|              User Password                   |
|                                              |
|                  Argon2id                    |
|                 /       \                    |
|                /         \                   |
|       Authentication   Data Encryption       |
|           Key               Key              |
+----------------------+-----------------------+
                       |
                       v
+----------------------------------------------+
|                  SQLite                      |
|                                              |
|     Encrypted item names and item data       |
+----------------------------------------------+
```

 ## Threat Model

 The current design is intended to protect sensitive password-manager data against unauthorized access to stored encrypted item data and interception of application messages.

 The design assumes:

- The client application has not been compromised.
- The server application has not been compromised.
- The server's private signing key remains secret.
- Users choose sufficiently strong passwords.
- The client correctly validates the server certificate.
- The client correctly verifies the handshake signature.
- Cryptographic primitives are implemented and used correctly.
- The operating system and runtime environment are trusted.

 The design does not automatically protect against:

- A compromised client device.
- Malware running on the client.
- A compromised server.
- Malware running on the server.
- Theft of the server private key.
- Weak user passwords.
- Offline password guessing against stolen database data.
- Attackers able to modify trusted client software.
- Compromise of backup files.
- Memory inspection by a sufficiently privileged attacker.

 ## Zero-Knowledge Considerations

 This project should **not currently be described as a zero-knowledge password manager** in the strict sense.

 The server does not permanently store the user's plaintext password. However, the server receives the user's password during authentication and password changes and performs password-based key derivation itself.

 For example, during authentication:

```
Flutter Client
     |
     | password
     v
Go Backend
     |
     +-- Argon2id(password, salt_auth)
     |
     +-- Argon2id(password, salt_data)
```

 The server therefore knows the password during the authentication operation.

 The server also derives the user's data encryption key and uses that key to decrypt and encrypt password-manager items.

 This is fundamentally different from a strict zero-knowledge architecture in which the server cannot obtain the user's password or plaintext vault encryption key.

 The current design provides **encrypted storage and encrypted transport**, but it is not a strict zero-knowledge architecture.

 ## Why the Server Can Still Access Data

 Although plaintext passwords are not stored in the database, the server has access to the user's password during authentication.

 The server can derive:

```
userKey = Argon2id(password, salt_data)
```

 and use `userKey` to decrypt stored password-manager items.

 Therefore:

```
Database theft
        |
        v
Encrypted item payloads
        |
        X
No password/userKey available directly
```

 but:

```
Compromised server
        |
        v
Receives user password
        |
        v
Derives userKey
        |
        v
Can decrypt user data
```

 This is an important security distinction.

 ## Security Considerations

 This project uses established cryptographic primitives, but correct use of cryptography involves more than selecting strong algorithms.

 Before using this project as a production password manager, consider:

- Independently reviewing the cryptographic protocol.
- Verifying the Flutter client's certificate validation.
- Verifying the Flutter client's handshake signature validation.
- Reviewing the Argon2id parameters for the target hardware.
- Maintaining authentication rate limiting.
- Maintaining WebSocket message-size limits.
- Maintaining read and write deadlines.
- Maintaining concurrent connection limits.
- Reviewing logout and session expiration behavior.
- Protecting the server's private signing key.
- Protecting database backup files.
- Avoiding logs containing passwords or decrypted data.
- Avoiding logs containing session keys or user encryption keys.
- Considering secure memory handling for sensitive key material.
- Reviewing session lifecycle and concurrent access.
- Considering full-database encryption if database metadata confidentiality is required.
- Performing security testing and an independent audit.
- Considering a zero-knowledge architecture if server confidentiality is a security requirement.

 ## Limitations

 Current implementation limitations include:

- Database metadata is not encrypted.
- SQLite backup files require separate protection.
- The server receives the user's password during authentication.
- The server derives and uses the user's data encryption key.
- The current architecture is therefore not strictly zero-knowledge.
- Session state is stored in server memory.
- There is no persistent login/session token mechanism.
- Changing a password requires decrypting and re-encrypting all user items.
- Item lookup requires decrypting stored item names.
- Production deployment requires proper certificate management.
- The client must correctly validate the server certificate and handshake signature.
- The cryptographic protocol should be independently reviewed before production use.
- Secure password-manager deployment requires protection of the server, client devices, certificates, backups, and operating systems.

 ## Production Warning

 This project is a personal/development-stage password manager and should not be assumed to provide the same security guarantees as an independently audited commercial password manager.

 In particular, cryptographic correctness does not by itself guarantee overall application security.

 Before storing important real-world credentials, perform a thorough security review covering:

- Cryptographic protocol design.
- Authentication.
- Authorization.
- Session lifecycle.
- Rate limiting.
- WebSocket handling.
- Database security.
- Backup security.
- Client-side key handling.
- Server-side key handling.
- Memory handling.
- Logging.
- Dependency security.
- Certificate management.
- Update and deployment security.
- Recovery and password-reset design.
- Offline attack resistance.

 Use strong, unique passwords and protect the server and client devices appropriately.