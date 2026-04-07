"""
VinFast Battery - Charge Log Manager
Flask Backend Server
"""
import os, uuid
from datetime import datetime, timedelta
from flask import Flask, render_template, request, jsonify

app = Flask(__name__)
app.secret_key = os.urandom(24)

# In-memory data store
vehicles_db = {
    "VF-OPES-001": {"vehicleId":"VF-OPES-001","vehicleName":"VinFast Opes","currentOdo":1250,"totalCharges":45,"avatarColor":"#00C853"},
    "VF-KLARA-002": {"vehicleId":"VF-KLARA-002","vehicleName":"VinFast Klara S","currentOdo":3820,"totalCharges":112,"avatarColor":"#448AFF"},
}
charge_logs_db = []

def _seed():
    now = datetime.now()
    for i, (sb, eb, odo, d) in enumerate([(15,100,1230,1),(30,95,1180,3),(8,100,1100,5),(22,88,1020,7),(5,100,950,10)]):
        charge_logs_db.append({"logId":str(uuid.uuid4()),"vehicleId":"VF-OPES-001",
            "startTime":(now-timedelta(days=d,hours=8)).isoformat(),"endTime":(now-timedelta(days=d,hours=5)).isoformat(),
            "startBatteryPercent":sb,"endBatteryPercent":eb,"odoAtCharge":odo})
_seed()

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/vehicles")
def get_vehicles():
    return jsonify({"success":True,"data":list(vehicles_db.values())})

@app.route("/api/vehicles/<vid>")
def get_vehicle(vid):
    v = vehicles_db.get(vid)
    return jsonify({"success":True,"data":v}) if v else (jsonify({"success":False,"error":"Không tìm thấy xe"}),404)

@app.route("/api/charge-logs")
def get_charge_logs():
    vid = request.args.get("vehicleId")
    logs = [l for l in charge_logs_db if not vid or l["vehicleId"]==vid]
    logs = sorted(logs, key=lambda x:x["startTime"], reverse=True)
    return jsonify({"success":True,"data":logs})

@app.route("/api/charge-logs", methods=["POST"])
def add_charge_log():
    data = request.get_json()
    if not data:
        return jsonify({"success":False,"error":"Dữ liệu không hợp lệ"}),400
    vid = data.get("vehicleId","")
    vehicle = vehicles_db.get(vid)
    if not vehicle:
        return jsonify({"success":False,"error":"Không tìm thấy xe"}),404
    try:
        sb,eb,odo = int(data["startBatteryPercent"]),int(data["endBatteryPercent"]),int(data["odoAtCharge"])
    except:
        return jsonify({"success":False,"error":"Pin và ODO phải là số nguyên"}),400
    if not(0<=sb<=100) or not(0<=eb<=100):
        return jsonify({"success":False,"error":"Mức pin phải từ 0-100%"}),400
    if eb<=sb:
        return jsonify({"success":False,"error":f"Pin sau sạc ({eb}%) phải > trước sạc ({sb}%)"}),400
    if odo<vehicle["currentOdo"]:
        return jsonify({"success":False,"error":f"ODO ({odo}km) phải ≥ ODO hiện tại ({vehicle['currentOdo']}km)"}),400
    try:
        st,et = datetime.fromisoformat(data["startTime"]),datetime.fromisoformat(data["endTime"])
    except:
        return jsonify({"success":False,"error":"Thời gian không hợp lệ"}),400
    if et<=st:
        return jsonify({"success":False,"error":"Thời gian kết thúc phải sau bắt đầu"}),400
    new_log = {"logId":str(uuid.uuid4()),"vehicleId":vid,"startTime":st.isoformat(),"endTime":et.isoformat(),
        "startBatteryPercent":sb,"endBatteryPercent":eb,"odoAtCharge":odo}
    charge_logs_db.append(new_log)
    vehicles_db[vid]["currentOdo"]=odo
    vehicles_db[vid]["totalCharges"]=vehicles_db[vid].get("totalCharges",0)+1
    return jsonify({"success":True,"data":new_log,"message":"Đã lưu nhật ký sạc thành công!"}),201

@app.route("/api/charge-logs/<log_id>", methods=["DELETE"])
def delete_charge_log(log_id):
    global charge_logs_db
    n = len(charge_logs_db)
    charge_logs_db = [l for l in charge_logs_db if l["logId"]!=log_id]
    return jsonify({"success":True}) if len(charge_logs_db)<n else (jsonify({"success":False,"error":"Không tìm thấy"}),404)

@app.route("/api/stats/<vid>")
def get_stats(vid):
    logs = [l for l in charge_logs_db if l["vehicleId"]==vid]
    if not logs:
        return jsonify({"success":True,"data":{"totalCharges":0,"avgChargeGain":0,"totalEnergyGained":0,"avgChargeDuration":0}})
    tc=len(logs); tg=sum(l["endBatteryPercent"]-l["startBatteryPercent"] for l in logs)
    ds=[]
    for l in logs:
        try: ds.append((datetime.fromisoformat(l["endTime"])-datetime.fromisoformat(l["startTime"])).total_seconds()/3600)
        except: pass
    return jsonify({"success":True,"data":{"totalCharges":tc,"avgChargeGain":round(tg/tc,1),"totalEnergyGained":tg,
        "avgChargeDuration":round(sum(ds)/len(ds),1) if ds else 0}})

if __name__=="__main__":
    print("\n⚡ VinFast Battery - Charge Log Manager")
    print("🌐 http://localhost:5000\n")
    app.run(debug=True, host="0.0.0.0", port=5000)
