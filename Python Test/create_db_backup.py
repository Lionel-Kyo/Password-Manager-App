import asyncio
from client import VaultClient
import actions


async def run_test_suite():
    with open("server_cert.pem", "r") as f:
        cert_pem = f.read()

    client = VaultClient(host="127.0.0.1", port=8080, expected_cert_pem=cert_pem)

    try:
        print("=== 1. Connecting & Handshake ===")
        await client.connect()
        print("Handshake successful! Encrypted channel established.\n")

        print("=== Backup Database ===")
        res = await actions.backup_database(client)
        print(f"Response: {res}\n")

    except Exception as e:
        print(f"[Error occurred]: {e}")
    finally:
        await client.close()
        print("=== Connection Closed ===")


if __name__ == "__main__":
    asyncio.run(run_test_suite())