import asyncio
import json

import websockets

from crypto import CryptoSession, MAX_WEB_SOCKET_MSG_BYTES


class VaultClient:
    RECEIVE_TIMEOUT = 10

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 8080,
        expected_cert_pem: str | None = None,
    ):
        self.uri = f"ws://{host}:{port}/ws"
        self.ws = None
        self.expected_cert_pem = expected_cert_pem
        self.crypto = CryptoSession()
        self.is_connected = False

    async def connect(self):
        """Connect to WebSocket server and perform authenticated handshake."""

        # A new WebSocket connection must use a fresh ephemeral key pair.
        self.crypto.reset()

        # Close any existing connection first.
        if self.ws is not None:
            await self.close()

        try:
            self.ws = await websockets.connect(
                self.uri,
                max_size=MAX_WEB_SOCKET_MSG_BYTES,
                open_timeout=10,
                ping_interval=20,
                ping_timeout=10,
                close_timeout=5,
            )

            handshake_payload = self.crypto.get_handshake_payload()
            await self.ws.send(handshake_payload)

            response = await asyncio.wait_for(
                self.ws.recv(),
                timeout=self.RECEIVE_TIMEOUT,
            )

            if isinstance(response, bytes):
                response = response.decode("utf-8")

            self.crypto.process_handshake_response(
                response,
                expected_cert_pem=self.expected_cert_pem,
            )

            self.is_connected = True

        except Exception as e:
            await self.close()
            raise ConnectionError(
                f"Authenticated handshake failed: {e}"
            ) from e

    async def send_command(self, payload: dict) -> dict:
        """Encrypt, send, and decrypt a single server command."""

        if not self.is_connected or self.ws is None:
            await self.connect()

        if self.ws is None:
            raise ConnectionError(
                "WebSocket connection is not available."
            )

        try:
            encrypted_json = self.crypto.encrypt_payload(payload)

            if len(encrypted_json.encode("utf-8")) > MAX_WEB_SOCKET_MSG_BYTES:
                raise ValueError("Encrypted message exceeds maximum size.")

            await self.ws.send(encrypted_json)

            response = await asyncio.wait_for(
                self.ws.recv(),
                timeout=self.RECEIVE_TIMEOUT,
            )

            if isinstance(response, bytes):
                response = response.decode("utf-8")

            response_envelope = json.loads(response)

            if not isinstance(response_envelope, dict):
                raise ValueError("Invalid server response.")

            encrypted_payload = response_envelope.get(
                "payload"
            )

            if not isinstance(encrypted_payload, str):
                raise ValueError("Invalid encrypted response envelope.")

            return self.crypto.decrypt_envelope(encrypted_payload)

        except asyncio.TimeoutError as e:
            self.is_connected = False
            await self.close()
            raise TimeoutError("Server response timeout.") from e

        except websockets.exceptions.ConnectionClosed as e:
            self.is_connected = False

            await self.close()

            raise ConnectionError(
                f"WebSocket connection closed: {e}"
            ) from e

    async def logout(self):
        """
        Explicitly log out from the server.

        The server clears the authenticated session and the
        WebSocket connection is then closed. Local cryptographic
        session state is also cleared.
        """

        if not self.is_connected or self.ws is None:
            await self.close()
            return

        try:
            response = await self.send_command({
                "action": "Logout",
            })

            if not response.get("success", False):
                raise RuntimeError(
                    response.get(
                        "error",
                        "Logout failed.",
                    )
                )

        finally:
            # Always close the connection and wipe local
            # cryptographic session state.
            await self.close()

    async def close(self):
        """
        Close the WebSocket connection and clear local
        authentication/cryptographic state.
        """

        self.is_connected = False

        if self.ws is not None:
            try:
                await self.ws.close()
            except Exception:
                pass
            finally:
                self.ws = None

        # Remove the current AES session key and ephemeral
        # X25519 key pair.
        self.crypto.clear_session()