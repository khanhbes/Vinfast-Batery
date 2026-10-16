"""Shelly Cloud dispatch-gate state in Azure Table Storage (Task 123).

The gate protocol (``cloud_dispatch.CloudDispatchGate``) is unchanged: one
lease per Shelly credential, 1.1 s completion spacing, OFF priority and 429
cooldown. Only the store moves from a Firestore transaction (nam5, ~0.5 s per
round trip from East Asia) to an entity next to the API, updated with ETag
optimistic concurrency. Plain ``requests`` + the Container Apps managed
identity, so the worker image needs no extra SDK.

Every API and worker process must use the same store at the same time.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
import os
import re
import threading
import time
from urllib.parse import quote

import requests

_PARTITION = "shellyCloud"
_STORAGE_RESOURCE = "https://storage.azure.com/"
_API_VERSION = "2020-12-06"
_MAX_ATTEMPTS = 8


def _encode(value):
    if isinstance(value, datetime):
        return {"__dt__": value.isoformat()}
    if isinstance(value, dict):
        return {key: _encode(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_encode(item) for item in value]
    return value


def _decode(value):
    if isinstance(value, dict):
        if set(value) == {"__dt__"}:
            return datetime.fromisoformat(value["__dt__"])
        return {key: _decode(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_decode(item) for item in value]
    return value


class ManagedIdentityToken:
    """Storage bearer token from the Container Apps identity endpoint."""

    def __init__(self, client_id: str | None = None, session=None, clock=time.time):
        self.client_id = client_id or os.environ.get("AZURE_CLIENT_ID") or None
        self.http = session or requests.Session()
        self.clock = clock
        self._token: str | None = None
        self._expires = 0.0
        self._lock = threading.Lock()

    def get(self) -> str:
        with self._lock:
            if self._token and self.clock() < self._expires - 300:
                return self._token
            endpoint = os.environ.get("IDENTITY_ENDPOINT")
            header = os.environ.get("IDENTITY_HEADER")
            params = {"resource": _STORAGE_RESOURCE}
            if self.client_id:
                params["client_id"] = self.client_id
            if endpoint and header:
                params["api-version"] = "2019-08-01"
                response = self.http.get(endpoint, params=params,
                                         headers={"X-IDENTITY-HEADER": header}, timeout=5)
            else:
                params["api-version"] = "2018-02-01"
                response = self.http.get("http://169.254.169.254/metadata/identity/oauth2/token",
                                         params=params, headers={"Metadata": "true"}, timeout=5)
            if response.status_code != 200:
                raise RuntimeError("dispatchIdentityUnavailable")
            body = response.json()
            token = body.get("access_token")
            if not isinstance(token, str) or not token:
                raise RuntimeError("dispatchIdentityUnavailable")
            try:
                expires = float(body.get("expires_on"))
            except (TypeError, ValueError):
                expires = self.clock() + 600
            self._token, self._expires = token, expires
            return token


class AzureTableDispatchStore:
    def __init__(self, account: str, table: str = "shellyDispatch", *, token=None,
                 session=None, timeout: float = 5.0, wall_clock=None):
        if not re.fullmatch(r"[a-z0-9]{3,24}", account or ""):
            raise RuntimeError("dispatchStoreMisconfigured")
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{2,62}", table or ""):
            raise RuntimeError("dispatchStoreMisconfigured")
        self.base = f"https://{account}.table.core.windows.net"
        self.table = table
        self.http = session or requests.Session()
        self.token = token or ManagedIdentityToken(session=self.http)
        self.timeout = timeout
        self.now = wall_clock or (lambda: datetime.now(timezone.utc))

    def _headers(self, **extra) -> dict:
        return {
            "Authorization": f"Bearer {self.token.get()}",
            "x-ms-version": _API_VERSION,
            "x-ms-date": time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime()),
            "Accept": "application/json;odata=nometadata",
            "DataServiceVersion": "3.0;NetFx",
            **extra,
        }

    def _entity_url(self, key: str, partition: str = _PARTITION) -> str:
        return (f"{self.base}/{self.table}(PartitionKey='{partition}',"
                f"RowKey='{quote(key, safe='')}')")

    def _read(self, key: str, partition: str = _PARTITION) -> tuple[dict, str | None]:
        response = self.http.get(self._entity_url(key, partition), headers=self._headers(), timeout=self.timeout)
        if response.status_code == 404:
            return {}, None
        if response.status_code != 200:
            raise RuntimeError("cloudRateLimiterUnavailable")
        raw = response.json().get("state")
        try:
            data = _decode(json.loads(raw)) if raw else {}
        except (TypeError, ValueError):
            raise RuntimeError("cloudLimiterMalformed") from None
        if not isinstance(data, dict):
            raise RuntimeError("cloudLimiterMalformed")
        return data, response.headers.get("ETag")

    def _write(self, key: str, data: dict, etag: str | None, partition: str = _PARTITION) -> bool:
        """True when stored; False when another process won the race."""
        entity = {"PartitionKey": partition, "RowKey": key,
                  "state": json.dumps(_encode(data), separators=(",", ":"), sort_keys=True)}
        if etag is None:
            response = self.http.post(f"{self.base}/{self.table}", json=entity,
                                      headers=self._headers(**{"Content-Type": "application/json",
                                                               "Prefer": "return-no-content"}),
                                      timeout=self.timeout)
            if response.status_code == 409:
                return False
            if response.status_code not in (201, 204):
                raise RuntimeError("cloudRateLimiterUnavailable")
            return True
        response = self.http.put(self._entity_url(key, partition), json=entity,
                                 headers=self._headers(**{"Content-Type": "application/json",
                                                          "If-Match": etag}),
                                 timeout=self.timeout)
        if response.status_code == 412:
            return False
        if response.status_code != 204:
            raise RuntimeError("cloudRateLimiterUnavailable")
        return True

    def change(self, fingerprint: str, action):
        """Same contract as the Firestore transaction: action(data, now) ->
        (updated, result); the write is atomic against concurrent changes."""
        if not re.fullmatch(r"[a-f0-9]{64}", fingerprint or ""):
            raise RuntimeError("cloudLimiterMalformed")
        return self.change_entity(_PARTITION, fingerprint, action)

    def change_entity(self, partition: str, key: str, action):
        """Atomic read-modify-write of one entity (ETag), any partition.
        action(data, now) -> (updated, result); unchanged data is not written."""
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{0,62}", partition or "")                 or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", key or ""):
            raise RuntimeError("controlStateMalformed")
        for _ in range(_MAX_ATTEMPTS):
            data, etag = self._read(key, partition)
            updated, result = action(data, self.now())
            if updated == data:
                return result
            if self._write(key, updated, etag, partition):
                return result
        raise RuntimeError("cloudRateLimiterUnavailable")

    def read_entity(self, partition: str, key: str) -> dict:
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]{0,62}", partition or "")                 or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", key or ""):
            raise RuntimeError("controlStateMalformed")
        return self._read(key, partition)[0]


def control_state_in_table() -> bool:
    """Task 123 phase 1: worker lease/health live in the table too. API and
    worker must switch together (a mismatch fails closed: ON is refused)."""
    return (os.environ.get("SHELLY_CONTROL_STATE") or "").strip().lower() == "table"


_store_lock = threading.Lock()
_store: AzureTableDispatchStore | None = None


def configured_store() -> AzureTableDispatchStore | None:
    """Process-wide store when SHELLY_DISPATCH_TABLE_ACCOUNT is set."""
    global _store
    account = (os.environ.get("SHELLY_DISPATCH_TABLE_ACCOUNT") or "").strip()
    if not account:
        return None
    with _store_lock:
        if _store is None:
            table = (os.environ.get("SHELLY_DISPATCH_TABLE") or "shellyDispatch").strip()
            _store = AzureTableDispatchStore(account, table)
        return _store
