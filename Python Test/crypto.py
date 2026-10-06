import base64
import datetime
import json
import os

from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, x25519
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF


MAX_WEB_SOCKET_MSG_BYTES = 1 * 1024 * 1024 # 1 MiB

HANDSHAKE_INFO = b"websocket-ecc-aes-handshake"

AES_KEY_SIZE = 32
AES_NONCE_SIZE = 12
AES_TAG_SIZE = 16


class CryptoSession:
    def __init__(self):
        self.private_key = None
        self.public_key = None
        self.session_key: bytes | None = None

        self.reset()

    def reset(self) -> None:
        """
        Generate a new ephemeral X25519 key pair.

        This should be called for every new WebSocket connection so that
        every connection gets a fresh session key.
        """
        self.private_key = x25519.X25519PrivateKey.generate()
        self.public_key = self.private_key.public_key()
        self.session_key = None

    def clear_session(self) -> None:
        """
        Clear the current session key.

        The next connection will generate a fresh X25519 key pair.
        """
        self.session_key = None

    def get_handshake_payload(self) -> str:
        """Return unencrypted JSON handshake payload."""

        if self.public_key is None:
            raise ValueError("Client key pair is not initialized.")

        pub_bytes = self.public_key.public_bytes_raw()

        return json.dumps({
            "action": "handshake",
            "client_public_key": base64.b64encode(
                pub_bytes
            ).decode("utf-8"),
        })

    def process_handshake_response(
        self,
        response_json: str,
        expected_cert_pem: str | None = None,
    ) -> None:
        """
        Process and verify the server handshake response.

        Verification steps:

        1. Validate handshake status.
        2. Decode the server X25519 public key.
        3. Parse and validate the server certificate.
        4. Verify certificate pinning when configured.
        5. Verify ECDSA signature over:
               ServerPublicKey + ClientPublicKey
        6. Derive AES-256 session key using:
               X25519 ECDH + HKDF-SHA256
        """

        if self.private_key is None or self.public_key is None:
            raise ValueError("Client key pair is not initialized.")

        resp = json.loads(response_json)

        if not isinstance(resp, dict):
            raise ValueError("Invalid handshake response.")

        if resp.get("status") != "ok":
            raise ValueError(f"Handshake rejected by server: {resp.get('status')}")

        try:
            server_pub_bytes = base64.b64decode(resp["server_public_key"], validate=True)
            cert_pem_bytes = base64.b64decode(resp["certificate"], validate=True)
            signature_bytes = base64.b64decode(resp["signature"], validate=True)

        except (KeyError, ValueError) as e:
            raise ValueError("Handshake failed: Invalid handshake encoding.") from e

        # X25519 public keys are exactly 32 bytes.
        if len(server_pub_bytes) != 32:
            raise ValueError(
                "Handshake failed: Invalid server public key."
            )

        if not signature_bytes:
            raise ValueError(
                "Handshake failed: Empty server signature."
            )

        # ------------------------------------------------------------
        # Certificate validation
        # ------------------------------------------------------------

        try:
            cert = x509.load_pem_x509_certificate(
                cert_pem_bytes
            )
        except Exception as e:
            raise ValueError(
                "Handshake failed: Invalid server certificate."
            ) from e

        now = datetime.datetime.now(datetime.timezone.utc)

        # Newer cryptography versions provide *_utc.
        try:
            not_valid_before = cert.not_valid_before_utc
            not_valid_after = cert.not_valid_after_utc
        except AttributeError:
            # Compatibility with older cryptography versions.
            not_valid_before = cert.not_valid_before.replace(
                tzinfo=datetime.timezone.utc
            )
            not_valid_after = cert.not_valid_after.replace(
                tzinfo=datetime.timezone.utc
            )

        if now < not_valid_before or now > not_valid_after:
            raise ValueError(
                "Handshake failed: Server certificate expired "
                "or not yet valid."
            )

        # ------------------------------------------------------------
        # Certificate pinning
        # ------------------------------------------------------------

        if expected_cert_pem is not None:
            expected_cert_bytes = expected_cert_pem.encode(
                "utf-8"
            )

            if cert_pem_bytes.strip() != expected_cert_bytes.strip():
                raise ValueError(
                    "Handshake failed: Certificate pinning mismatch."
                )

        # ------------------------------------------------------------
        # Verify ECDSA signature
        # ------------------------------------------------------------

        client_pub_bytes = self.public_key.public_bytes_raw()

        signed_data = (
            server_pub_bytes +
            client_pub_bytes
        )

        ecdsa_pub_key = cert.public_key()

        if not isinstance(
            ecdsa_pub_key,
            ec.EllipticCurvePublicKey,
        ):
            raise ValueError(
                "Handshake failed: Certificate public key "
                "is not an ECDSA key."
            )

        try:
            ecdsa_pub_key.verify(
                signature_bytes,
                signed_data,
                ec.ECDSA(hashes.SHA256()),
            )
        except InvalidSignature as e:
            raise ValueError(
                "Handshake failed: Invalid server signature."
            ) from e

        # ------------------------------------------------------------
        # Derive session key
        # ------------------------------------------------------------

        self.compute_session_key(server_pub_bytes)

    def compute_session_key(
        self,
        server_pub_bytes: bytes,
    ) -> None:
        """
        Derive a 256-bit AES session key using:

            X25519 ECDH
            +
            HKDF-SHA256
        """

        if self.private_key is None:
            raise ValueError("Client private key is not initialized.")

        if len(server_pub_bytes) != 32:
            raise ValueError("Invalid server public key length.")

        server_public_key = (
            x25519.X25519PublicKey.from_public_bytes(server_pub_bytes)
        )

        shared_secret = self.private_key.exchange(server_public_key)

        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=AES_KEY_SIZE,
            salt=None,
            info=HANDSHAKE_INFO,
        )

        self.session_key = hkdf.derive(shared_secret)

    def encrypt_payload(
        self,
        payload: dict,
    ) -> str:
        """
        Encrypt a dictionary using AES-256-GCM.

        The resulting payload contains:

            nonce + ciphertext + authentication tag

        encoded as Base64 inside a JSON envelope.
        """

        if not self.session_key:
            raise ValueError("Session key not initialized. Perform handshake first.")

        if not isinstance(payload, dict):
            raise ValueError(
                "Payload must be a dictionary."
            )

        json_bytes = json.dumps(
            payload,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")

        if len(json_bytes) > MAX_WEB_SOCKET_MSG_BYTES:
            raise ValueError("Payload too large.")

        aesgcm = AESGCM(self.session_key)

        nonce = os.urandom(AES_NONCE_SIZE)

        ciphertext_and_tag = aesgcm.encrypt(
            nonce,
            json_bytes,
            None,
        )

        combined = nonce + ciphertext_and_tag

        envelope = json.dumps({ "payload": base64.b64encode(combined).decode("utf-8") })

        envelope_size = len(
            envelope.encode("utf-8")
        )

        if envelope_size > MAX_WEB_SOCKET_MSG_BYTES:
            raise ValueError("Encrypted payload too large.")

        return envelope

    def decrypt_envelope(
        self,
        encrypted_payload: str,
    ) -> dict:
        """
        Decrypt a Base64 encoded AES-GCM payload.
        """

        if not self.session_key:
            raise ValueError("Session key not initialized.")

        if not isinstance(encrypted_payload, str):
            raise ValueError("Encrypted payload must be a string.")

        try:
            combined = base64.b64decode(
                encrypted_payload,
                validate=True,
            )
        except ValueError as e:
            raise ValueError("Invalid encrypted payload encoding.") from e

        minimum_size = AES_NONCE_SIZE + AES_TAG_SIZE

        if len(combined) < minimum_size:
            raise ValueError("Encrypted payload too short.")

        # Prevent oversized encrypted payloads from being
        # passed to AES-GCM.
        if len(combined) > MAX_WEB_SOCKET_MSG_BYTES:
            raise ValueError("Encrypted payload too large.")

        nonce = combined[:AES_NONCE_SIZE]

        ciphertext_and_tag = combined[AES_NONCE_SIZE:]

        aesgcm = AESGCM(self.session_key)

        try:
            decrypted_bytes = aesgcm.decrypt(
                nonce,
                ciphertext_and_tag,
                None,
            )
        except Exception as e:
            raise ValueError("Failed to decrypt encrypted payload.") from e

        if len(decrypted_bytes) > MAX_WEB_SOCKET_MSG_BYTES:
            raise ValueError("Decrypted payload too large.")

        try:
            result = json.loads(decrypted_bytes.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            raise ValueError("Invalid decrypted JSON payload.") from e

        if not isinstance(result, dict):
            raise ValueError("Decrypted payload must be a dictionary.")

        return result
