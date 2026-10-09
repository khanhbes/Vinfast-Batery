"""Shared terminal-event delivery, independent of Flask and AI initialization.

Retains the legacy mark-before-send dedupe policy; not an exactly-once outbox.
"""
from datetime import datetime, timezone


def send_terminal_push(uid, *, session_id, state, vehicle_id=None, target_percent=None,
                       route="smart_charge", db=None, messaging=None, firebase_app=None,
                       local_tokens=None, local_deliveries=None):
    event_key = f"smart_charge:{session_id}:{state}"
    local_deliveries = local_deliveries if local_deliveries is not None else set()
    if event_key in local_deliveries:
        return {"sent": 0, "deduplicated": True}
    payload = {"event": "smart_charge", "eventKey": event_key,
               "sessionId": str(session_id), "vehicleId": str(vehicle_id or ""),
               "state": str(state), "targetPercent": str(target_percent or ""), "route": route}
    tokens, refs = [], []
    if db is not None:
        ref = db.collection("PushDeliveries").document(event_key.replace("/", "_"))
        if ref.get().exists:
            return {"sent": 0, "deduplicated": True}
        for doc in db.collection("users").document(uid).collection("pushTokens").stream():
            item = doc.to_dict() or {}
            if item.get("token"):
                tokens.append(item["token"])
                refs.append(doc.reference)
        ref.set({"uid": uid, "eventKey": event_key, "createdAt": datetime.now(timezone.utc)})
    else:
        tokens = [item["token"] for (owner, _), item in (local_tokens or {}).items()
                  if owner == uid and item.get("token")]
        local_deliveries.add(event_key)
    if not tokens or messaging is None:
        return {"sent": 0, "deduplicated": False}
    # FCM accepts at most 500 tokens per multicast; same UID on many phones is valid.
    sent = failed = 0
    for start in range(0, len(tokens), 500):
        message = messaging.MulticastMessage(tokens=tokens[start:start + 500], data=payload,
            notification=messaging.Notification(title="VinFast Battery", body=f"Smart Charge: {state}"))
        kwargs = {"app": firebase_app} if firebase_app is not None else {}
        result = messaging.send_each_for_multicast(message, **kwargs)
        sent += result.success_count
        failed += result.failure_count
        for index, response in enumerate(result.responses):
            error = getattr(response, "exception", None)
            if not response.success and error and refs and str(getattr(error, "code", "")) in {
                    "messaging/registration-token-not-registered", "messaging/invalid-registration-token"}:
                refs[start + index].delete()
    return {"sent": sent, "failed": failed, "deduplicated": False}
