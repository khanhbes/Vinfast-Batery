from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any

from models import SmartChargingSession

logger = logging.getLogger(__name__)

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    HAS_FIREBASE_ADMIN = True
except ImportError:
    HAS_FIREBASE_ADMIN = False


class FirestoreSessionSync:
    """Syncs terminal charging sessions and detailed telemetry from Gateway to Firestore."""

    def __init__(
        self,
        service_account_path: str | Path | None = None,
        enabled: bool | None = None,
    ) -> None:
        if enabled is not None:
            self.enabled = enabled
        else:
            self.enabled = os.getenv("ENABLE_FIRESTORE_SYNC", "false").strip().lower() in ("true", "1", "yes")

        self.service_account_path = service_account_path or os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
        self._db: Any = None
        self._initialized = False

        if self.enabled:
            self._init_firebase()

    def _init_firebase(self) -> None:
        if not HAS_FIREBASE_ADMIN:
            logger.warning("[FirestoreSync] firebase-admin is not installed; sync disabled")
            self.enabled = False
            return

        try:
            if not firebase_admin._apps:
                if self.service_account_path and Path(self.service_account_path).exists():
                    cred = credentials.Certificate(str(self.service_account_path))
                    firebase_admin.initialize_app(cred)
                else:
                    # Default application credentials
                    firebase_admin.initialize_app()
            self._db = firestore.client()
            self._initialized = True
            logger.info("[FirestoreSync] Initialized Firestore client successfully")
        except Exception as e:
            logger.warning("[FirestoreSync] Could not initialize Firebase Admin: %s. Sync disabled.", e)
            self.enabled = False

    def sync_session(
        self,
        session: SmartChargingSession,
        telemetry_samples: list[dict[str, Any]] | None = None,
    ) -> bool:
        """Syncs session document and telemetry subcollection to Firestore."""
        if not self.enabled or not self._initialized or self._db is None:
            return False

        try:
            doc_ref = self._db.collection("ChargeLogs").document(session.session_id)
            session_data = {
                "sessionId": session.session_id,
                "vehicleId": session.vehicle_id,
                "state": session.state.value,
                "strategy": session.strategy.value,
                "startSoc": session.start_soc,
                "targetSoc": session.target_soc,
                "actualEndSoc": session.actual_end_soc,
                "actualEndSocSource": session.actual_end_soc_source,
                "energyUsedWh": session.energy_used_wh,
                "whPerSocPercent": session.wh_per_soc_percent,
                "trainingEligible": session.training_eligible,
                "predictedMinutes": session.predicted_minutes,
                "startedAt": session.started_at.isoformat() if session.started_at else None,
                "stoppedAt": session.stopped_at.isoformat() if session.stopped_at else None,
                "stopReason": session.stop_reason.value if session.stop_reason else None,
                "shadowMode": session.shadow_mode,
                "telemetrySamplesCount": session.telemetry_samples_count,
                "updatedAt": session.updated_at.isoformat(),
                "syncedFromGateway": True,
            }
            # Remove None values
            cleaned = {k: v for k, v in session_data.items() if v is not None}
            doc_ref.set(cleaned, merge=True)

            # Sync telemetry samples subcollection if provided
            if telemetry_samples:
                telemetry_coll = doc_ref.collection("smartChargeTelemetry")
                # Batch in groups of 400 (Firestore max is 500)
                batch_size = 400
                for i in range(0, len(telemetry_samples), batch_size):
                    batch = self._db.batch()
                    chunk = telemetry_samples[i : i + batch_size]
                    for idx, sample in enumerate(chunk):
                        sample_id = f"sample_{i + idx:06d}"
                        sample_ref = telemetry_coll.document(sample_id)
                        batch.set(sample_ref, sample)
                    batch.commit()

            logger.info(
                "[FirestoreSync] Synced session %s (samples: %d) to Firestore",
                session.session_id,
                len(telemetry_samples) if telemetry_samples else 0,
            )
            return True
        except Exception as e:
            logger.error("[FirestoreSync] Error syncing session %s to Firestore: %s", session.session_id, e)
            return False
