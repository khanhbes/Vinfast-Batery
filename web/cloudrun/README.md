# Cloud Run deployment contract

The API image is deployed to project `vinfast-873db` in `asia-southeast1`.
The service uses Firebase Application Default Credentials from its runtime
service account; no Firebase Admin JSON is mounted or packaged.

Before applying `api-service.yaml`, replace `REGION` with
`asia-southeast1`, create the referenced Secret Manager secrets, and grant the
runtime service account only the Firebase/Firestore permissions it needs.

Build and deploy from a trusted CI identity:

```powershell
gcloud builds submit web --tag asia-southeast1-docker.pkg.dev/vinfast-873db/vinfast-battery/api:1.1.5-rc --project vinfast-873db --dockerfile Dockerfile.api
gcloud run services replace web/cloudrun/api-service.yaml --region asia-southeast1 --project vinfast-873db
```

The first deployment is validated on the managed `run.app` hostname. A custom
`api.<owned-domain>` hostname is mapped through an external HTTPS load
balancer/serverless NEG with a Google-managed certificate before setting
`PRODUCTION_API_BASE_URL` in GitHub Actions.

The AI and reconciliation workers are intentionally separate rollout units.
Core readiness must remain usable when AI is degraded; Smart Charging must not
be enabled until the device-timer/watchdog worker and Shelly readback have
passed hardware sign-off.

Cloud Scheduler/Cloud Run Job creation is intentionally not automated here:
the repository still needs the production runtime service account, scheduler
identity and a one-shot reconciliation entry point before a minute-by-minute
job can be enabled safely.
