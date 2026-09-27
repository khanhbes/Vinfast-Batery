import pytest
from datetime import datetime, timezone, timedelta
from shelly.connection_codes import ConnectionCodeStore, ShellyConnectionCode


def test_generate_and_redeem_code():
    store = ConnectionCodeStore(firestore_db=None)

    code_entry = store.generate(
        device_id="shelly-plug-001",
        device_name="Shelly Plug S Garage",
        model="S3PL-00112EU",
        cloud_host="https://shelly-104-eu.shelly.cloud",
        cloud_auth_key="secret-auth-key-12345",
        lan_address="192.168.1.50",
        local_password="local-password",
        created_by="admin_uid",
        expires_hours=24,
        max_redemptions=2,
        note="Test code for QA",
    )

    assert len(code_entry.code) == 6
    assert code_entry.device_id == "shelly-plug-001"
    assert code_entry.is_usable is True
    assert code_entry.redemption_count == 0

    # Public dict should NOT leak plaintext secrets
    public_dict = code_entry.to_public_dict()
    assert "cloudAuthKey" not in public_dict
    assert "localPassword" not in public_dict
    assert public_dict["hasCloudAuthKey"] is True
    assert public_dict["hasLocalPassword"] is True

    # Redeem #1
    redeemed, err = store.redeem(code_entry.code, "user_001")
    assert err is None
    assert redeemed is not None
    assert redeemed.redemption_count == 1
    assert redeemed.to_profile_dict()["cloudAuthKey"] == "secret-auth-key-12345"
    assert redeemed.to_profile_dict()["deviceId"] == "shelly-plug-001"

    # Redeem #2
    redeemed, err = store.redeem(code_entry.code.lower(), "user_002") # case-insensitive
    assert err is None
    assert redeemed.redemption_count == 2

    # Redeem #3 should fail (max redemptions reached)
    redeemed, err = store.redeem(code_entry.code, "user_003")
    assert redeemed is None
    assert "hết số lần" in err


def test_revoked_code():
    store = ConnectionCodeStore(firestore_db=None)
    code_entry = store.generate(
        device_id="dev-2",
        device_name="Shelly Revoke",
        model="S3PL-00112EU",
        cloud_host="https://shelly.cloud",
        cloud_auth_key="key",
        created_by="admin",
    )

    assert store.revoke(code_entry.code) is True
    redeemed, err = store.redeem(code_entry.code, "user")
    assert redeemed is None
    assert "thu hồi" in err


def test_expired_code():
    store = ConnectionCodeStore(firestore_db=None)
    code_entry = store.generate(
        device_id="dev-3",
        device_name="Shelly Expired",
        model="S3PL-00112EU",
        cloud_host="https://shelly.cloud",
        cloud_auth_key="key",
        created_by="admin",
        expires_hours=-1, # already expired
    )

    assert code_entry.is_expired is True
    assert code_entry.is_usable is False
    redeemed, err = store.redeem(code_entry.code, "user")
    assert redeemed is None
    assert "hết hạn" in err


def test_invalid_code():
    store = ConnectionCodeStore(firestore_db=None)
    redeemed, err = store.redeem("NONEXIST", "user")
    assert redeemed is None
    assert "không tồn tại" in err


def test_atomic_redemption_is_single_owner_and_idempotent_for_same_user():
    store = ConnectionCodeStore(firestore_db=None)
    item = store.generate(
        device_id="owned-device", device_name="Plug", model="S3PL-00112EU",
        cloud_host="https://shelly.cloud", cloud_auth_key="secret", created_by="admin",
        max_redemptions=9,
    )
    first, error = store.redeem_atomic(item.code, "uid-a")
    assert error is None and first is item
    retry, error = store.redeem_atomic(item.code, "uid-a")
    assert error is None and retry is item
    other, error = store.redeem_atomic(item.code, "uid-b")
    assert other is None and error
    assert item.redemption_count == 1


def test_save_device_and_auto_generate_code():
    store = ConnectionCodeStore(firestore_db=None)

    # Save Shelly 1 -> should generate code 1
    dev1, code1 = store.save_device_and_generate_code(
        device_id="shelly-01",
        device_name="Shelly Trạm Sạc 1",
        model="S3PL-00112EU",
        cloud_host="https://shelly-104-eu.shelly.cloud",
        cloud_auth_key="key-shelly-1",
        created_by="admin",
        note="Gara 1",
    )
    assert dev1["deviceId"] == "shelly-01"
    assert len(code1.code) == 6
    assert code1.device_id == "shelly-01"

    # Save Shelly 2 -> should generate code 2
    dev2, code2 = store.save_device_and_generate_code(
        device_id="shelly-02",
        device_name="Shelly Trạm Sạc 2",
        model="SNSW-001P16EU",
        cloud_host="https://shelly-104-eu.shelly.cloud",
        cloud_auth_key="key-shelly-2",
        created_by="admin",
        note="Gara 2",
    )
    assert dev2["deviceId"] == "shelly-02"
    assert len(code2.code) == 6
    assert code2.device_id == "shelly-02"
    assert code1.code != code2.code

    # List devices should list BOTH devices, each with its own active pairing code
    devices = store.list_devices()
    assert len(devices) == 2

    dev1_info = next(d for d in devices if d["deviceId"] == "shelly-01")
    dev2_info = next(d for d in devices if d["deviceId"] == "shelly-02")

    assert dev1_info["latestCode"] == code1.code
    assert dev1_info["hasUsableCode"] is True
    assert dev1_info["displayName"] == "Shelly Trạm Sạc 1"

    assert dev2_info["latestCode"] == code2.code
    assert dev2_info["hasUsableCode"] is True
    assert dev2_info["displayName"] == "Shelly Trạm Sạc 2"

    # Delete device 1 -> should remove device 1 and revoke its code
    assert store.delete_device("shelly-01") is True
    remaining = store.list_devices()
    # Now only device 2 has usable code
    dev1_after = next((d for d in remaining if d["deviceId"] == "shelly-01"), None)
    if dev1_after:
        assert dev1_after["hasUsableCode"] is False
    assert code1.is_revoked is True
