"""ModelStore — versioned on-disk storage for AI models.

Layout:
    models/<type>/
        manifest.json            -> {"active": "<version>", "versions": [...]}
        v_<version>.<ext>        -> model files (any extension: .pkl, .h5, .pt, .onnx, ...)

Retention: keep at most MAX_VERSIONS; older ones are deleted on upload.
"""
from __future__ import annotations

import json
import os
import shutil
import threading
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any

MAX_VERSIONS = 10


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class ModelStore:
    def __init__(self, root_dir: str) -> None:
        self.root = os.path.abspath(root_dir)
        os.makedirs(self.root, exist_ok=True)
        self.manifest_path = os.path.join(self.root, "manifest.json")
        self._lock = threading.Lock()
        if not os.path.isfile(self.manifest_path):
            self._write_manifest({"active": None, "versions": []})

    # ── Manifest IO ──────────────────────────────────────────────
    def _read_manifest(self) -> Dict[str, Any]:
        try:
            with open(self.manifest_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {"active": None, "versions": []}

    def _write_manifest(self, data: Dict[str, Any]) -> None:
        tmp = self.manifest_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.replace(tmp, self.manifest_path)

    # ── Queries ──────────────────────────────────────────────────
    def list_versions(self) -> List[Dict[str, Any]]:
        data = self._read_manifest()
        active = data.get("active")
        out = []
        for v in data.get("versions", []):
            v = dict(v)
            v["active"] = v.get("version") == active
            path = self.path_of(v["version"], v.get("ext", ".pkl"))
            try:
                v["sizeBytes"] = os.path.getsize(path) if os.path.isfile(path) else 0
            except Exception:
                v["sizeBytes"] = 0
            v["path"] = path
            out.append(v)
        return out

    def active_version(self) -> Optional[str]:
        return self._read_manifest().get("active")

    def _ext_for(self, version: str) -> str:
        """Look up the stored extension for a version, default .pkl."""
        data = self._read_manifest()
        for v in data.get("versions", []):
            if v.get("version") == version:
                return v.get("ext", ".pkl")
        return ".pkl"

    def active_path(self) -> Optional[str]:
        v = self.active_version()
        if not v:
            return None
        path = self.path_of(v)
        return path if os.path.isfile(path) else None

    def path_of(self, version: str, ext: Optional[str] = None) -> str:
        if ext is None:
            ext = self._ext_for(version)
        return os.path.join(self.root, f"v_{version}{ext}")

    def has_version(self, version: str) -> bool:
        return os.path.isfile(self.path_of(version)) and any(
            v.get("version") == version for v in self._read_manifest().get("versions", [])
        )

    # ── Mutations ────────────────────────────────────────────────
    def save_from_temp(self, tmp_path: str, version: str, note: Optional[str],
                       ext: str = ".pkl") -> Dict[str, Any]:
        """Move temp file to final location + register in manifest (inactive by default)."""
        with self._lock:
            if any(v.get("version") == version for v in self._read_manifest().get("versions", [])):
                raise ValueError(f"Version '{version}' đã tồn tại")
            final = self.path_of(version, ext)
            shutil.move(tmp_path, final)
            meta = {
                "version": version,
                "uploadedAt": _utc_now_iso(),
                "note": note or "",
                "ext": ext,
            }
            data = self._read_manifest()
            versions = data.get("versions", [])
            versions.append(meta)
            data["versions"] = versions
            self._write_manifest(data)
            self._enforce_retention()
            return meta

    def activate(self, version: str) -> None:
        with self._lock:
            data = self._read_manifest()
            versions = [v.get("version") for v in data.get("versions", [])]
            if version not in versions:
                raise ValueError(f"Version '{version}' không tồn tại")
            if not os.path.isfile(self.path_of(version)):
                raise FileNotFoundError(f"Model file cho version '{version}' bị thiếu")
            data["active"] = version
            data["activatedAt"] = _utc_now_iso()
            self._write_manifest(data)

    def deactivate(self) -> None:
        """Clear the active version without deleting it."""
        with self._lock:
            data = self._read_manifest()
            if "active" in data:
                del data["active"]
            if "activatedAt" in data:
                del data["activatedAt"]
            self._write_manifest(data)

    def remove(self, version: str) -> None:
        with self._lock:
            data = self._read_manifest()
            if data.get("active") == version:
                raise ValueError("Không thể xóa version đang active")
            data["versions"] = [v for v in data.get("versions", []) if v.get("version") != version]
            self._write_manifest(data)
            try:
                os.remove(self.path_of(version))
            except FileNotFoundError:
                pass

    def _enforce_retention(self) -> None:
        data = self._read_manifest()
        versions = data.get("versions", [])
        if len(versions) <= MAX_VERSIONS:
            return
        # Sort by uploadedAt ascending, never drop active
        active = data.get("active")
        versions_sorted = sorted(versions, key=lambda v: v.get("uploadedAt", ""))
        to_keep: List[Dict[str, Any]] = []
        # Keep newest MAX_VERSIONS but always include active
        keep_set = set(v.get("version") for v in versions_sorted[-MAX_VERSIONS:])
        if active:
            keep_set.add(active)
        for v in versions_sorted:
            if v.get("version") in keep_set:
                to_keep.append(v)
            else:
                try:
                    os.remove(self.path_of(v["version"]))
                except FileNotFoundError:
                    pass
        data["versions"] = to_keep
        self._write_manifest(data)

    def seed_from_legacy(self, legacy_pkl_path: str) -> Optional[str]:
        """If no versions yet and a legacy file exists, copy it in as v1."""
        if self.active_version() or self._read_manifest().get("versions"):
            return None
        if not os.path.isfile(legacy_pkl_path):
            return None
        version = "legacy-1"
        _, ext = os.path.splitext(legacy_pkl_path)
        ext = ext or ".pkl"
        final = self.path_of(version, ext)
        shutil.copy2(legacy_pkl_path, final)
        data = self._read_manifest()
        data["versions"] = [{
            "version": version,
            "uploadedAt": _utc_now_iso(),
            "note": f"seeded from legacy {os.path.basename(legacy_pkl_path)}",
            "ext": ext,
        }]
        data["active"] = version
        data["activatedAt"] = _utc_now_iso()
        self._write_manifest(data)
        return version
