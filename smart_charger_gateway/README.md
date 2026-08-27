# Local Smart Charger Gateway

FastAPI gateway between the Flutter app and a Shelly Plug S Gen3. Prediction
sessions are metadata-only (`monitor_only`); they never control the relay.

```powershell
cd smart_charger_gateway
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
$env:SHELLY_IP = "192.168.1.3"
.\.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Keep port 8000 and the Shelly device on the trusted local network. Do not
forward either port to the Internet.
