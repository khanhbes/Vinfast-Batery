"""QA 157: read one vehicle's learned charge profile. READ ONLY.

Runs inside the production API container (tools/read_charge_ledger.ps1
sends it there). Reads two documents: the vehicle and its
AiVehicleProfiles entry. Prints the capacity fields, the learned profile
(samples, ledger, Wh per 1 %, layers) and the training reports, zlib +
base64 between <<< and >>>. No account id, name or email is printed.
"""
import base64
import hashlib
import json
import os
import zlib

import firebase_admin
from firebase_admin import credentials, firestore

V = "__VEHICLE__"
raw = os.environ["FIREBASE_CREDENTIALS_JSON"].strip()
cred = json.loads(raw if raw.startswith("{") else base64.b64decode(raw))
app = firebase_admin.initialize_app(credentials.Certificate(cred), name="qa157")
db = firestore.client(app)
vehicle = db.collection("Vehicles").document(V).get().to_dict() or {}
uid = vehicle.get("ownerUid", "")
key = hashlib.sha256((uid + ":" + V).encode()).hexdigest()
profile = db.collection("AiVehicleProfiles").document(key).get().to_dict() or {}
out = {
    "vehicle": {
        k: vehicle.get(k)
        for k in ("modelName", "nominalCapacityWh", "batteryCapacityWh",
                  "batteryCapacity", "stateOfHealth", "currentOdo",
                  "batteryChemistry")
    },
    "found": bool(profile),
    "learned": profile.get("learned"),
    "trainingReports": profile.get("trainingReports"),
    "lastTrainedAt": profile.get("lastTrainedAt"),
}
data = json.dumps(out, default=str).encode()
print("<<<" + base64.b64encode(zlib.compress(data, 9)).decode() + ">>>")
