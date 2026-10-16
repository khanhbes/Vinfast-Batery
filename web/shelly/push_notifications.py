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
            notification=messaging.Notification(title="VinFast Battery", body=terminal_message(state)))
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


_TERMINAL_MESSAGES = {
    "completed": "Đã sạc xong theo hẹn giờ. Shelly đã tự ngắt.",
    "cancelled": "Đã dừng sạc. Shelly đã xác nhận tắt.",
    "interrupted": "Phiên sạc bị ngắt trước giờ dự kiến. Mở app để kiểm tra.",
    "failed": "Phiên sạc cần kiểm tra. Mở app để xem trạng thái ổ cắm.",
}


def terminal_message(state) -> str:
    """User-facing Vietnamese text (was "Smart Charge: <state>", Task 125)."""
    return _TERMINAL_MESSAGES.get(str(state), "Phiên sạc đã kết thúc. Mở app để xem chi tiết.")


def send_state_push(uid, *, session_id, state, vehicle_id=None, db=None, messaging=None,
                    firebase_app=None, local_tokens=None):
    """Data-only "refresh now" signal to every phone of the account (Task 123).

    No visible notification (the phone that sent the command needs none) and
    no dedupe record: it carries no state to trust, phones re-read the server.
    """
    payload = {"event": "smart_charge", "eventKey": f"smart_charge:{session_id}:{state}",
               "sessionId": str(session_id), "vehicleId": str(vehicle_id or ""),
               "state": str(state), "silent": "1"}
    if db is not None:
        tokens = [item.get("token") for item in
                  (doc.to_dict() or {} for doc in
                   db.collection("users").document(uid).collection("pushTokens").limit(20).stream())
                  if item.get("token")]
    else:
        tokens = [item["token"] for (owner, _), item in (local_tokens or {}).items()
                  if owner == uid and item.get("token")]
    if not tokens or messaging is None:
        return {"sent": 0}
    message = messaging.MulticastMessage(
        tokens=tokens[:500], data=payload,
        android=messaging.AndroidConfig(priority="high"))
    kwargs = {"app": firebase_app} if firebase_app is not None else {}
    result = messaging.send_each_for_multicast(message, **kwargs)
    return {"sent": result.success_count, "failed": result.failure_count}
