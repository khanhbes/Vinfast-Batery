"""QA 166: read one vehicle's latest charging sessions with their 1-minute
curves. READ ONLY.

Runs inside the production API container (tools/read_charge_sessions.ps1
sends it there). Reads the vehicle and the owner's latest sessions, keeps
those of this vehicle and prints, zlib + base64 between <<< and >>>, the
fields battery health needs: start and end %, where the start % came from,
energy, power, why it stopped and the curve (time, power, energy). No
account id, name, email or device id is printed.
"""
import base64
import json
import os
import zlib

import firebase_admin
from firebase_admin import credentials, firestore

V = "__VEHICLE__"
LIMIT = int("__LIMIT__")
raw = os.environ["FIREBASE_CREDENTIALS_JSON"].strip()
cred = json.loads(raw if raw.startswith("{") else base64.b64decode(raw))
app = firebase_admin.initialize_app(credentials.Certificate(cred), name="qa166")
db = firestore.client(app)
vehicle = db.collection("Vehicles").document(V).get().to_dict() or {}
uid = vehicle.get("ownerUid", "")
KEEP = ("session_id", "state", "strategy", "stop_mode", "created_at", "stopped_at", "stop_reason",
        "start_soc", "target_soc", "estimated_soc", "actual_end_soc", "end_soc_source",
        "energy_used_wh", "energy_quality", "average_power_w", "peak_power_w",
        "average_voltage_v", "shelly_temperature_c", "gauge_trust_level",
        "start_soc_source", "start_soc_age_min", "full_detected_at", "tail_entry_w")
sessions = []
if uid:
    query = (db.collection("users").document(uid).collection("smartChargingSessions")
             .order_by("created_at", direction=firestore.Query.DESCENDING).limit(LIMIT * 2))
    for snapshot in query.stream():
        data = snapshot.to_dict() or {}
        if data.get("vehicle_id") != V:
            continue
        item = {key: data.get(key) for key in KEEP}
        item["curve"] = [[item_.get("t"), round(float(item_.get("p") or 0), 1),
                          round(float(item_.get("wh") or 0), 2)]
                         for item_ in (data.get("telemetry_samples") or []) if isinstance(item_, dict)]
        sessions.append(item)
        if len(sessions) >= LIMIT:
            break
out = {
    "vehicle": {key: vehicle.get(key) for key in (
        "nominalCapacityWh", "batteryChemistry", "currentBattery", "batteryDataSource",
        "batteryDataUpdatedAt", "batteryCutoff")},
    "sessions": sessions,
}
data = json.dumps(out, default=str).encode()
print("<<<" + base64.b64encode(zlib.compress(data, 9)).decode() + ">>>")
