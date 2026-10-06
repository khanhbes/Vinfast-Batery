"""Run inside API container only, with an explicit supervised-test flag.

Input is private JSON on stdin: profile and current providerSource. Output is
an allowlisted evidence object, never credentials, identities or raw errors.
No ownership/profile/safety certification is created. One transient device
operation lease is released only after fresh OFF readback.
"""
import contextlib
from datetime import datetime, timezone
import io
import json
import sys
import uuid


def main():
    result = {"operationId": str(uuid.uuid4()), "onCommands": 0, "offCommands": 0,
              "status": "Blocked", "samples": [], "httpStatuses": [],
              "startedAt": datetime.now(timezone.utc).isoformat()}
    provider = repository = binding = uid = None
    claimed = False
    try:
        if "--supervised-no-load-confirmed" not in sys.argv:
            raise RuntimeError("supervisionNotConfirmed")
        request = json.load(sys.stdin)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            import server
        if server._firestore_db is None:
            raise RuntimeError("firebaseUnavailable")
        import requests
        from shelly.models import DeviceBinding
        from shelly.repositories import SmartChargeRepository
        import shelly.providers.vault_cloud as module
        # Only this short-lived QA process loads current source; API workers
        # are not restarted or patched underneath an existing charging session.
        exec(compile(request["providerSource"], "qa-vault-cloud", "exec"), module.__dict__)
        repository = SmartChargeRepository(server._firestore_db)
        profile = request["profile"]
        device = profile["deviceId"]
        owner = repository.db.collection("shellyDeviceOwners").document(
            repository._device_owner_doc_id(device)).get().to_dict() or {}
        members = repository._membership_uids(owner)
        uid = owner.get("ownerUid")
        if uid not in members:
            uid = members[0] if len(members) == 1 else None
        if not uid:
            raise RuntimeError("membershipContextUnavailable")
        binding = DeviceBinding(device, "Supervised QA", "S3PL-00112EU", 3,
                                "vault_cloud", owner_uid=uid)

        class ProbeProfiles:
            def restore_synced_profile(self, account, device_id):
                if account != uid or device_id != device:
                    return None
                return {**profile, "model": "S3PL-00112EU"}

            def reserve_cloud_request_slot(self, *args):
                return repository.reserve_cloud_request_slot(*args)

        class SafeHttp(requests.Session):
            def post(self, *args, **kwargs):
                response = super().post(*args, **kwargs)
                result["httpStatuses"].append(response.status_code)
                return response

        class ObservedProvider(module.VaultCloudControlProvider):
            def turn_on_with_timer(self, target, duration):
                if result["onCommands"] or duration != 5:
                    raise RuntimeError("secondOnForbidden")
                result["onCommands"] += 1
                return super().turn_on_with_timer(target, duration)

            def turn_off(self, target):
                result["offCommands"] += 1
                return super().turn_off(target)

            def get_status(self, target):
                status = super().get_status(target)
                result["samples"].append({
                    "at": datetime.now(timezone.utc).isoformat(),
                    "relayOn": status.relay, "timerSeconds": status.timer_remaining,
                    "powerW": status.power_w, "voltageV": status.voltage_v,
                    "currentA": status.current_a, "energyWh": status.energy_wh,
                    "temperatureC": status.temperature_c})
                return status

        provider = ObservedProvider(ProbeProfiles(), session=SafeHttp())
        snapshot = provider.get_snapshot(binding)
        if str(snapshot.get("gen") or "").upper() != "G2":
            raise RuntimeError("cloudIdentityMismatch")
        result["model"] = snapshot.get("code")
        if not repository.claim_device_session(uid, device, result["operationId"]):
            raise RuntimeError("deviceLeaseUnavailable")
        claimed = True
        evidence = provider.run_no_load_test(binding)
        result["evidence"] = evidence
        result["status"] = "Pass" if evidence.get("noLoadTestVerified") else "Fail"
    except Exception as error:
        result["errorCode"] = getattr(error, "code", type(error).__name__)
        # RuntimeError text is printed only if it is our own allowlisted code.
        if str(error) in {"membershipContextUnavailable", "deviceLeaseUnavailable",
                          "supervisionNotConfirmed", "firebaseUnavailable", "cloudIdentityMismatch"}:
            result["errorCode"] = str(error)
        if result["onCommands"]:
            result["status"] = "Fail"
    finally:
        if claimed and provider and binding:
            try:
                final = provider.get_status(binding)
                result["finalOffVerified"] = final.relay is False
                if result["finalOffVerified"]:
                    repository.release_device_session(uid, binding.device_id, result["operationId"])
                    lease = repository.db.collection("shellyDeviceLocks").document(
                        repository._device_owner_doc_id(binding.device_id)).get()
                    result["testLeaseReleased"] = not lease.exists
                else:
                    result["status"] = "Fail"
                    result["physicalDisconnectRequired"] = True
            except Exception as error:
                result["finalOffVerified"] = False
                result["status"] = "Fail"
                result["physicalDisconnectRequired"] = True
                result["finalReadbackErrorCode"] = getattr(error, "code", type(error).__name__)
        result["endedAt"] = datetime.now(timezone.utc).isoformat()
        print(json.dumps(result))
    return 0 if result["status"] == "Pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
