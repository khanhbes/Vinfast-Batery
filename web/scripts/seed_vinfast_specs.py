"""
seed_vinfast_specs.py — Seed Firestore VinFastModelSpecs từ catalog reviewed.

Cách dùng (từ thư mục `web/`):
    python scripts/seed_vinfast_specs.py [--dry-run] [--source PATH]

Mặc định đọc catalog từ:
    ../app/assets/vinfast_specs_fallback.json

Yêu cầu:
- Đặt biến môi trường GOOGLE_APPLICATION_CREDENTIALS trỏ tới service-account JSON
  HOẶC để file `firebase-service-account.json` cạnh script này.
- pip install firebase-admin
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    print("[ERROR] Thiếu firebase-admin. Cài bằng: pip install firebase-admin",
          file=sys.stderr)
    sys.exit(1)


COLLECTION = "VinFastModelSpecs"
DEFAULT_CATALOG = (
    Path(__file__).resolve().parent.parent.parent
    / "app" / "assets" / "vinfast_specs_fallback.json"
)


def init_firebase() -> firestore.Client:
    if firebase_admin._apps:
        return firestore.client()

    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not cred_path:
        local = Path(__file__).resolve().parent / "firebase-service-account.json"
        if local.exists():
            cred_path = str(local)

    if cred_path:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
    else:
        # Fallback: ADC (gcloud login)
        firebase_admin.initialize_app()

    return firestore.client()


def load_catalog(path: Path) -> list[dict]:
    if not path.exists():
        raise FileNotFoundError(f"Không tìm thấy catalog: {path}")
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError("Catalog phải là JSON array")
    return raw


def upsert_specs(db: firestore.Client, specs: list[dict], dry_run: bool) -> None:
    batch = db.batch() if not dry_run else None
    now_iso = datetime.now(timezone.utc).isoformat()

    written = 0
    for spec in specs:
        model_id = spec.get("modelId")
        if not model_id:
            print(f"  [SKIP] Bỏ qua entry thiếu modelId: {spec}")
            continue

        payload = dict(spec)
        payload["updatedAt"] = now_iso
        payload.setdefault("source", "vinfast_official")

        ref = db.collection(COLLECTION).document(model_id)
        if dry_run:
            print(f"  [DRY] {model_id} ← {payload['modelName']}")
        else:
            assert batch is not None
            batch.set(ref, payload, merge=True)
            print(f"  [SET] {model_id} ← {payload['modelName']}")
        written += 1

    if not dry_run and batch is not None:
        batch.commit()

    print(f"\n✅ Hoàn tất. {written} spec đã được {'giả lập' if dry_run else 'ghi'} vào {COLLECTION}.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed VinFast model specs")
    parser.add_argument("--source", type=Path, default=DEFAULT_CATALOG,
                        help=f"Path tới catalog JSON (mặc định: {DEFAULT_CATALOG})")
    parser.add_argument("--dry-run", action="store_true",
                        help="Chỉ in ra không ghi Firestore")
    args = parser.parse_args()

    print(f"📂 Catalog: {args.source}")
    specs = load_catalog(args.source)
    print(f"   {len(specs)} spec sẽ được seed.\n")

    if not args.dry_run:
        db = init_firebase()
    else:
        db = None  # type: ignore

    if args.dry_run:
        print("🧪 Dry-run mode — không ghi Firestore.")
        for spec in specs:
            print(f"  [DRY] {spec.get('modelId')} ← {spec.get('modelName')}")
        print(f"\nTotal: {len(specs)}")
        return 0

    upsert_specs(db, specs, dry_run=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
