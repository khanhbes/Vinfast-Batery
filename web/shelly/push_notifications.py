"""Shared terminal-event delivery, independent of Flask and AI initialization.

Retains the legacy mark-before-send dedupe policy; not an exactly-once outbox.
"""
from datetime import datetime, timedelta, timezone


def send_terminal_push(uid, *, session_id, state, vehicle_id=None, target_percent=None,
                       route="smart_charge", db=None, messaging=None, firebase_app=None,
                       local_tokens=None, local_deliveries=None, stop_reason=None,
                       estimated_soc=None, energy_wh=None):
    event_key = f"smart_charge:{session_id}:{state}"
    local_deliveries = local_deliveries if local_deliveries is not None else set()
    if event_key in local_deliveries:
        return {"sent": 0, "deduplicated": True}
    payload = {"event": "smart_charge", "eventKey": event_key,
               "sessionId": str(session_id), "vehicleId": str(vehicle_id or ""),
               "state": str(state), "targetPercent": str(target_percent or ""), "route": route,
               "stopReason": str(stop_reason or ""),
               "estimatedSoc": "" if estimated_soc is None else str(round(float(estimated_soc))),
               # A real charge ended: the app offers "type the % on the scooter".
               "promptActualSoc": "1" if float(energy_wh or 0) >= 30 else "0"}
    # QA 135: a safety cutoff rings on the urgent channel (alarm sound).
    urgent = str(stop_reason or "") in URGENT_STOP_REASONS
    if urgent:
        payload["urgent"] = "1"
    tokens, refs = [], []
    if db is not None:
        ref = db.collection("PushDeliveries").document(event_key.replace("/", "_"))
        if ref.get().exists:
            return {"sent": 0, "deduplicated": True}
        try:
            write_inbox_item(db, uid, session_id=session_id, state=state, vehicle_id=vehicle_id,
                             target_percent=target_percent, stop_reason=stop_reason,
                             estimated_soc=estimated_soc)
        except Exception:
            pass  # the inbox is a record; never block the push itself
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
            notification=messaging.Notification(
                title=terminal_title(state, stop_reason=stop_reason) if urgent else "Pinova",
                body=terminal_message(state, stop_reason=stop_reason, estimated_soc=estimated_soc)),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(channel_id=URGENT_CHANNEL, default_sound=True))
            if urgent else None)
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


URGENT_CHANNEL = "pinova_urgent"
URGENT_STOP_REASONS = {"safety_cutoff", "night_safety_cutoff"}

_TERMINAL_MESSAGES = {
    "completed": "Đã sạc xong theo hẹn giờ. Shelly đã tự ngắt.",
    "cancelled": "Đã dừng sạc. Shelly đã xác nhận tắt.",
    "interrupted": "Phiên sạc bị ngắt trước giờ dự kiến. Mở app để kiểm tra.",
    "failed": "Phiên sạc cần kiểm tra. Mở app để xem trạng thái ổ cắm.",
}


def terminal_message(state, *, stop_reason=None, estimated_soc=None) -> str:
    """User-facing Vietnamese text (was "Smart Charge: <state>", Task 125)."""
    reason = str(stop_reason or "")
    if reason == "target_reached":
        level = f" khoảng {round(float(estimated_soc))}%" if estimated_soc is not None else " mục tiêu"
        return (f"Đã sạc đến{level} (ước tính), ổ cắm đã tự ngắt. "
                "Nhập % trên đồng hồ xe để lần sau chính xác hơn.")
    if reason == "battery_full":
        return ("Pin đã đầy: công suất sạc đã ở dưới 40 W suốt 5 phút "
                "nên ổ cắm đã tự ngắt an toàn.")
    if reason == "charger_idle":
        return "Xe đã ngừng nhận điện (có thể pin đã đầy) nên ổ cắm đã tự ngắt."
    if reason == "ceiling_timer":
        return "Đã ngắt theo giới hạn thời gian an toàn trước khi ước tính đạt mục tiêu. Mở app để kiểm tra."
    if reason == "safety_cutoff":
        return "Đã ngắt sạc vì vượt ngưỡng an toàn. Mở app để xem chi tiết."
    if reason == "night_safety_cutoff":
        return ("Sạc đêm đã ngắt: ổ nóng, công suất bất thường hoặc sạc quá lâu. "
                "Kiểm tra ổ cắm và bộ sạc xe trước khi sạc lại.")
    return _TERMINAL_MESSAGES.get(str(state), "Phiên sạc đã kết thúc. Mở app để xem chi tiết.")


def terminal_title(state, *, stop_reason=None, estimated_soc=None) -> str:
    reason = str(stop_reason or "")
    if reason == "target_reached":
        return (f"Đã sạc đến ~{round(float(estimated_soc))}%" if estimated_soc is not None
                else "Đã sạc đến mục tiêu")
    titles = {
        "battery_full": "Pin đã đầy",
        "charger_idle": "Xe đã ngừng nhận điện",
        "ceiling_timer": "Đã ngắt theo giới hạn an toàn",
        "safety_cutoff": "Đã ngắt sạc vì an toàn",
        "night_safety_cutoff": "Sạc đêm đã ngắt vì an toàn",
    }
    if reason in titles:
        return titles[reason]
    return {
        "completed": "Đã sạc xong theo hẹn giờ",
        "cancelled": "Đã dừng sạc",
        "interrupted": "Phiên sạc bị ngắt",
        "failed": "Phiên sạc cần kiểm tra",
    }.get(str(state), "Phiên sạc đã kết thúc")


def write_inbox_item(db, uid, *, session_id, state, vehicle_id=None, target_percent=None,
                     stop_reason=None, estimated_soc=None):
    """One Notification Center item per session outcome (QA 129).

    Only the app wrote these before, and only when it saw the end itself: a
    charge the server cut while the app was closed (target, full battery,
    ceiling) never reached the inbox. Same id as the app's
    (``<uid>_sc_<session>_<state>``) so neither side duplicates the other;
    an existing item keeps its read state and only gets the precise text.
    """
    from urllib.parse import quote
    ref = db.collection("UserNotifications").document(f"{uid}_sc_{session_id}_{state}")
    text = {
        "title": terminal_title(state, stop_reason=stop_reason, estimated_soc=estimated_soc),
        "message": terminal_message(state, stop_reason=stop_reason, estimated_soc=estimated_soc),
        "payload": {"sessionId": str(session_id), "vehicleId": str(vehicle_id or ""),
                    "state": str(state), "stopReason": str(stop_reason or ""),
                    "targetPercent": target_percent},
    }
    if ref.get().exists:
        ref.set(text, merge=True)
        return
    vehicle = quote(str(vehicle_id or ""), safe="")
    session = quote(str(session_id), safe="")
    ref.set({**text, "userId": uid, "type": "system", "status": "unread",
             "createdAt": datetime.now(timezone.utc), "readAt": None, "imageUrl": None,
             "actionTarget": f"/smart-charge?vehicleId={vehicle}&sessionId={session}"})


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


PROGRESS_TTL_SECONDS = 150


def progress_payload(session, status, remaining_seconds) -> dict:
    """Data for the phone's "charging now" notification (Task 126).

    Strings only (FCM data). The phone shows it only while the app itself is
    not running its own live monitor, and the notification expires on its own
    if pushes stop, so a lost terminal push cannot leave a stale "charging".
    """
    soc = session.estimated_soc
    return {
        "event": "smart_charge_progress",
        "sessionId": str(session.session_id),
        "vehicleId": str(session.vehicle_id or ""),
        "soc": "" if soc is None else str(round(float(soc), 1)),
        "targetSoc": str(round(float(session.target_soc))),
        "stopMode": str(session.stop_mode or "timer"),
        "powerW": str(round(float(getattr(status, "power_w", 0) or 0))),
        "remainingSeconds": "" if remaining_seconds is None else str(max(0, int(remaining_seconds))),
        "ceilingAt": session.effective_stop_at.astimezone(timezone.utc).isoformat(),
        "sentAt": datetime.now(timezone.utc).isoformat(),
    }


def send_progress_push(uid, *, payload, db=None, messaging=None, firebase_app=None, local_tokens=None):
    """Data-only progress update to the account's phones; the newest replaces
    older ones in the FCM queue (collapse key) and expires quickly."""
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
        tokens=tokens[:500], data={key: str(value) for key, value in payload.items()},
        android=messaging.AndroidConfig(
            priority="high", ttl=timedelta(seconds=PROGRESS_TTL_SECONDS),
            collapse_key=f"progress-{payload.get('sessionId', '')}"[:60]))
    kwargs = {"app": firebase_app} if firebase_app is not None else {}
    result = messaging.send_each_for_multicast(message, **kwargs)
    return {"sent": result.success_count, "failed": result.failure_count}


def write_notice(db, uid, *, notice_id, title, message, action_target=None, payload=None):
    """A plain Notification Center item (QA 135: support replies, plan
    changes). Same shape as the app's own items; an existing id is updated
    and marked unread again."""
    ref = db.collection("UserNotifications").document(f"{uid}_{notice_id}"[:1400])
    ref.set({"userId": uid, "type": "system", "status": "unread", "title": title,
             "message": message, "payload": payload or {}, "imageUrl": None, "readAt": None,
             "actionTarget": action_target, "createdAt": datetime.now(timezone.utc)}, merge=True)


def send_user_push(uid, *, title, body, data=None, db=None, messaging=None, firebase_app=None,
                   local_tokens=None, urgent=False):
    """A visible notification to every phone of the account (QA 135);
    ``urgent`` rings on the alarm channel (night charging problems)."""
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
        tokens=tokens[:500], data={key: str(value) for key, value in (data or {}).items()},
        notification=messaging.Notification(title=title, body=body),
        android=messaging.AndroidConfig(
            priority="high",
            notification=(messaging.AndroidNotification(channel_id=URGENT_CHANNEL, default_sound=True)
                          if urgent else None)))
    kwargs = {"app": firebase_app} if firebase_app is not None else {}
    result = messaging.send_each_for_multicast(message, **kwargs)
    return {"sent": result.success_count, "failed": result.failure_count}
