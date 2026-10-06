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

        test_account = "testing"
        test_pass = "abcd"
        new_pass = "1234"

        print("=== RegisterUser ===")
        res = await actions.register_user(client, test_account, test_pass)
        print(f"Response: {res}\n")

        print("=== VerifyUser ===")
        res = await actions.verify_user(client, test_account, test_pass)
        print(f"Response: {res}\n")

        print("=== InsertItem ===")
        item_name = "GitHub Account"
        kvs = {"Username": "octocat", "Password": "SuperSecretGitHubPassword"}
        res = await actions.insert_item(client, item_name, kvs)
        print(f"Response: {res}\n")

        print("=== GetItemNames ===")
        res = await actions.get_item_names(client)
        print(f"Response: {res}\n")

        print("=== GetItem ===")
        res = await actions.get_item(client, item_name)
        print(f"Response: {res}\n")

        print("=== UpdateItem ===")
        updated_kvs = {"Username": "octocat_updated", "Password": "NewGitHubPassword999"}
        res = await actions.update_item(client, item_name, updated_kvs)
        print(f"Response: {res}\n")

        print("=== ModifyPassword ===")
        res = await actions.modify_password(client, test_pass, new_pass)
        print(f"Response: {res}\n")

        print("=== RemoveItem ===")
        res = await actions.remove_item(client, item_name)
        print(f"Response: {res}\n")

        print("=== Verify Removal (GetItemNames) ===")
        res = await actions.get_item_names(client)
        print(f"Response: {res}\n")

    except Exception as e:
        print(f"[Error occurred]: {e}")
    finally:
        await client.close()
        print("=== Connection Closed ===")


if __name__ == "__main__":
    asyncio.run(run_test_suite())