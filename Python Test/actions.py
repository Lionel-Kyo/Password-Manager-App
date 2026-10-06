from client import VaultClient


async def backup_database(client: VaultClient) -> dict:
    return await client.send_command({
        "action": "__BackupDatabase__",
    })

async def register_user(client: VaultClient, account: str, password: str) -> dict:
    return await client.send_command({
        "action": "Register",
        "account": account,
        "password": password,
    })


async def verify_user(client: VaultClient, account: str, password: str) -> dict:
    return await client.send_command({
        "action": "Verify",
        "account": account,
        "password": password,
    })

async def modify_password(client: VaultClient, old_password: str, new_password: str) -> dict:
    return await client.send_command({
        "action": "ModifyPassword",
        "old_password": old_password,
        "new_password": new_password,
    })


async def get_item_names(client: VaultClient) -> dict:
    return await client.send_command({
        "action": "GetItemNames",
    })


async def get_item(client: VaultClient, item_name: str) -> dict:
    return await client.send_command({
        "action": "GetItem",
        "item_name": item_name,
    })


async def insert_item(client: VaultClient, item_name: str, key_values: dict[str, str]) -> dict:
    return await client.send_command({
        "action": "InsertItem",
        "item_name": item_name,
        "key_values": key_values,
    })


async def update_item(client: VaultClient, item_name: str, key_values: dict[str, str]) -> dict:
    return await client.send_command({
        "action": "UpdateItem",
        "item_name": item_name,
        "key_values": key_values,
    })

async def update_item_order(client: VaultClient, ordered_item_names: list[str]) -> dict:
    return await client.send_command({
        "action": "UpdateItemOrder",
        "ordered_item_names": ordered_item_names,
    })


async def remove_item(client: VaultClient, item_name: str) -> dict:
    return await client.send_command({
        "action": "RemoveItem",
        "item_name": item_name,
    })