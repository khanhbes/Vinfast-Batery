"""QA 162: the capacity left ("Dung lượng pin còn lại") on the owner's own
charges, the old way (median of the last ten) against the new one (pooled,
weighted by % gained, gauge trust and age, outliers out).

Read-only: it reads the file `tools/read_charge_ledger.ps1` wrote
(`charge-ledger.local.json`, never committed) and prints numbers.

    python web/scripts/qa162_health_replay.py [charge-ledger.local.json]
"""
from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from shelly import charge_model  # noqa: E402

EFFICIENCY = charge_model.DEFAULT_EFFICIENCY


def _charges(path: Path) -> tuple[list[dict], float]:
    data = json.loads(path.read_text(encoding="utf-8"))
    learned = data.get("learned") or {}
    merged: dict[str, dict] = {}
    for key in ("ledger", "samples", "pending"):
        for index, item in enumerate(learned.get(key) or []):
            merged[str(item.get("sessionId") or f"{key}{index}")] = item
    nominal = float((data.get("vehicle") or {}).get("nominalCapacityWh") or 0)
    return sorted(merged.values(), key=lambda item: str(item.get("at") or "")), nominal


def _old(charges: list[dict], nominal: float) -> float | None:
    exact = [item for item in charges
             if not item.get("censored") and item.get("whPerPct")][-charge_model.HEALTH_RECENT_SAMPLES:]
    if not exact:
        return None
    wh = statistics.median(float(item["whPerPct"]) for item in exact)
    return round(wh * 100 * EFFICIENCY / nominal * 100, 1)


def _new(charges: list[dict], nominal: float) -> tuple[float | None, float | None]:
    result = charge_model.battery_health(charges, nominal)
    estimate, spread = result["estimate"], result["spread"] or {}
    return (estimate or {}).get("sohPct"), spread.get("uncertaintyPct")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "charge-ledger.local.json")
    charges, nominal = _charges(path)
    if not charges or nominal <= 0:
        print("Không có lần sạc hoặc dung lượng danh định.")
        return
    print(f"{len(charges)} lần sạc, danh định {nominal:.0f} Wh\n")
    print("Sau lần sạc        cũ (trung vị)   mới (gộp)   ±")
    old_steps, new_steps = [], []
    last_old = last_new = None
    for count in range(1, len(charges) + 1):
        prefix = charges[:count]
        old = _old(prefix, nominal)
        new, unc = _new(prefix, nominal)
        at = str(prefix[-1].get("at") or "")[:10]
        print(f"{count:2d}  {at}   {old if old is not None else '—':>8}   "
              f"{new if new is not None else '—':>10}   {unc if unc is not None else '—'}")
        if old is not None and last_old is not None:
            old_steps.append(abs(old - last_old))
        if new is not None and last_new is not None:
            new_steps.append(abs(new - last_new))
        last_old, last_new = old if old is not None else last_old, new if new is not None else last_new

    print("\nTừng lần sạc (cách mới):")
    for row in charge_model.battery_health(charges, nominal)["charges"]:
        print(f"  {str(row['at'])[:10]}  {row['startPct']:.0f}→{row['endPct']:.0f}%  "
              f"{row['sohPct'] if row['sohPct'] is not None else '—':>6}  "
              f"tin {row['trust']:<6} {'dùng' if row['used'] else 'bỏ: ' + str(row['reason'])}")

    half = len(charges) // 2
    print("\nTóm tắt:")
    print(f"  Số hiện tại: cũ {_old(charges, nominal)} · mới {_new(charges, nominal)[0]} "
          f"(±{_new(charges, nominal)[1]})")
    if old_steps and new_steps:
        print(f"  Thay đổi mỗi lần sạc mới: cũ trung bình {statistics.mean(old_steps):.1f}, "
              f"lớn nhất {max(old_steps):.1f} · mới trung bình {statistics.mean(new_steps):.1f}, "
              f"lớn nhất {max(new_steps):.1f} điểm")
    for name, fn in (("cũ", _old), ("mới", lambda c, n: _new(c, n)[0])):
        first, second = fn(charges[:half], nominal), fn(charges[half:], nominal)
        if first is not None and second is not None:
            print(f"  Hai nửa dữ liệu ({name}): {first} và {second}, lệch {abs(first - second):.1f}")


if __name__ == "__main__":
    main()
