"""Standalone reconciliation runtime: no Flask, AI, dotenv or local fallback."""
from __future__ import annotations

import base64
import json
import os
import re
from functools import partial

from .profile_vault import ShellyProfileVault
from .providers.vault_cloud import VaultCloudControlProvider
from .repositories import SmartChargeRepository
from .service import SmartChargeService
from .push_notifications import send_progress_push, send_terminal_push, send_user_push


class WorkerConfigurationError(RuntimeError):
    """Only this public code is logged, never configuration or SDK exceptions."""


def validate_configuration(env):
    scope = env.get("SMART_CHARGE_WORKER_SCOPE", "")
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", scope):
        raise WorkerConfigurationError("workerScopeNotConfigured")
    if env.get("SHELLY_PROVIDER", "vault_cloud") != "vault_cloud":
        raise WorkerConfigurationError("workerProviderUnsupported")
    if env.get("FIRESTORE_EMULATOR_HOST") or env.get("FIREBASE_AUTH_EMULATOR_HOST"):
        raise WorkerConfigurationError("workerEmulatorForbidden")
    try:
        vault = ShellyProfileVault(env.get("SHELLY_PROFILE_MASTER_KEY", ""))
        if not vault.configured:
            raise ValueError()
    except Exception:
        raise WorkerConfigurationError("workerVaultNotConfigured") from None
    try:
        interval = int(env.get("SMART_CHARGE_WORKER_POLL_SECONDS", "60"))
        port = int(env.get("SMART_CHARGE_WORKER_HEALTH_PORT", "8090"))
        if not 1 <= port <= 65535:
            raise ValueError()
    except (TypeError, ValueError):
        raise WorkerConfigurationError("workerTimingInvalid") from None
    # Probes are private even if an inherited env tries to expose them.
    if env.get("SMART_CHARGE_WORKER_HEALTH_HOST", "127.0.0.1") != "127.0.0.1":
        raise WorkerConfigurationError("workerProbeMustBePrivate")
    return scope, max(15, min(60, interval)), port


def create_worker_service():
    env = os.environ
    scope, _, _ = validate_configuration(env)
    # Importing this module never initializes ADC or discovers credential files.
    import firebase_admin
    from firebase_admin import credentials, firestore, messaging

    app = None
    try:
        raw = env.get("FIREBASE_CREDENTIALS_JSON", "").strip()
        if raw:
            if not raw.startswith("{"):
                raw = base64.b64decode(raw, validate=True).decode("utf-8")
            value = json.loads(raw)
            if not isinstance(value, dict) or value.get("type") != "service_account":
                raise ValueError()
            credential = credentials.Certificate(value)
        else:
            credential = credentials.ApplicationDefault()
        options = {"httpTimeout": 10}
        project = env.get("GOOGLE_CLOUD_PROJECT")
        if project:
            options["projectId"] = project
        app = firebase_admin.initialize_app(credential, options, name="smart-charge-worker")
        db = firestore.client(app=app)
        repository = SmartChargeRepository(db, worker_scope=scope)
        notifier = partial(send_terminal_push, db=db, messaging=messaging, firebase_app=app)
        def prediction_disabled(_):
            raise RuntimeError("workerPredictionDisabled")
        progress = partial(send_progress_push, db=db, messaging=messaging, firebase_app=app)
        service = SmartChargeService(repository, VaultCloudControlProvider(repository),
                                     prediction_disabled, push_notifier=notifier,
                                     progress_notifier=progress)
        # QA 135: night charging problems ring on every phone.
        service.night_alert = partial(send_user_push, db=db, messaging=messaging, firebase_app=app,
                                      data={"event": "night_alert", "urgent": "1"}, urgent=True)
        return service, partial(firebase_admin.delete_app, app)
    except Exception:
        if app is not None:
            firebase_admin.delete_app(app)
        raise WorkerConfigurationError("workerFirebaseUnavailable") from None
