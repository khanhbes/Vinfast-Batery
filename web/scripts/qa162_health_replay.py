"""QA 162: the capacity left ("Dung lượng pin còn lại") on the owner's own
charges, the old way (median of the last ten) against the new one (pooled,
weighted by % gained, gauge trust and age, outliers out).

Read-only: it reads the file `tools/read_charge_ledger.ps1` wrote
(`charge-ledger.local.json`, never committed) and prints numbers.

    python web/scripts/qa162_health_replay.py [charge-ledger.local.json] [--rated 400]

QA 166 (2): it ends with exactly what the server computes from that file (the
stored monthly log, samples + pending, the ledger, the learned wall power and
drift log; ``--rated`` = the charger's rated output), i.e. what the app will
show. Replaying the charges alone hid a "111.5 %" on 18/11/2026.
"""
from __future__ import annotations

import json
import statistics
import sys
from datetime import datetime, timezone
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

    print("\nTừng lần sạc (cách mới; ± là sai số của riêng lần đó, QA 166):")
    for row in charge_model.battery_health(charges, nominal)["charges"]:
        sigma = f"±{row['sigmaPct']}" if row.get("sigmaPct") is not None else ""
        kind = f" [{row['kind']}]" if row.get("kind") else ""
        print(f"  {str(row['at'])[:10]}  {row['startPct']:.0f}→{row['endPct']:.0f}%  "
              f"{row['sohPct'] if row['sohPct'] is not None else '—':>6} {sigma:>6}  "
              f"tin {row['trust']:<6} {'dùng' if row['used'] else 'bỏ: ' + str(row['reason'])}{kind}")

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

    # QA 164: against the battery's own start, and month by month.
    full = charge_model.battery_health(charges, nominal, history=charges)
    tracking, spread = full["tracking"], full["spread"] or {}
    print()
    print("So với lúc bắt đầu theo dõi (QA 164):")
    if tracking["status"] == "ready":
        print(f"  {tracking['relativePct']}% ±{tracking['uncertaintyPct']} "
              f"(mốc {str(tracking['since'])[:10]} → {str(tracking['until'])[:10]}, "
              f"{tracking['referenceCharges']} lần sạc)")
        for month in tracking["monthly"]:
            print(f"  {month['month']}: {month['relativePct']}% ({month['charges']} lần sạc)")
    else:
        print(f"  Đang lập mốc: cần thêm {tracking['needCharges']} lần sạc, {tracking['needDays']} ngày")
    if spread:
        # QA 166: what more charges cannot reduce, apart.
        systematic = full["systematic"] or {}
        print(f"  Dung lượng tuyệt đối: ±{spread['uncertaintyPct']} đo được; "
              f"{spread.get('totalLowPct')}–{spread.get('totalHighPct')}% khi tính cả hệ số "
              f"{systematic.get('factorLow')}–{systematic.get('factorHigh')} "
              f"({'đã đo' if systematic.get('factorMeasured') else 'chưa đo'}), danh định "
              f"±{systematic.get('nominalPct')}%, công tơ ±{systematic.get('meterPct')}%")
        sigmas = full.get("sigmas") or {}
        points = sigmas.get("points") or {}
        counts = sigmas.get("charges") or {}
        print("  Sai số đồng hồ của xe này (điểm %): "
              + ", ".join(f"{key} {points[key]} ({counts.get(key, 0)} lần)" for key in points))
    _server_view(path, nominal, _rated(sys.argv))


def _rated(argv: list[str]) -> float | None:
    if "--rated" in argv and argv.index("--rated") + 1 < len(argv):
        return float(argv[argv.index("--rated") + 1])
    return None


def _server_view(path: Path, nominal: float, rated: float | None) -> None:
    """QA 166 (2): what the server computes from the stored profile, i.e. what
    the app shows: the stored monthly log (and its reference) included."""
    learned = json.loads(path.read_text(encoding="utf-8")).get("learned") or {}
    result = charge_model.battery_health(
        [*(learned.get("samples") or []), *(learned.get("pending") or [])], nominal,
        history=learned.get("ledger") or [], now=datetime.now(timezone.utc),
        log=learned.get("healthLog"), charger_rated_w=rated,
        wall_power_w=learned.get("powerW"), drift_log=learned.get("driftLog"))
    estimate, spread = result["estimate"] or {}, result["spread"] or {}
    systematic, tracking = result["systematic"] or {}, result["tracking"] or {}
    print()
    print("Máy chủ sẽ tính (sổ tháng đang lưu, QA 166 (2)):")
    print(f"  Tuyệt đối {estimate.get('sohPct')}% ±{spread.get('uncertaintyPct')} "
          f"({spread.get('totalLowPct')}–{spread.get('totalHighPct')}%), hệ số {systematic.get('factor')} "
          f"({systematic.get('factorLow')}–{systematic.get('factorHigh')}, "
          f"{systematic.get('factorSource') or 'chưa đo'})")
    if tracking.get("status") == "ready":
        print(f"  So với mốc {tracking.get('relativePct')}% ±{tracking.get('uncertaintyPct')} "
              f"(mốc {str(tracking.get('since'))[:10]} → {str(tracking.get('until'))[:10]})")
    else:
        print(f"  Đang lập mốc: cần thêm {tracking.get('needCharges')} lần sạc, {tracking.get('needDays')} ngày")
    if result.get("gaugeDrift"):
        drift = result["gaugeDrift"]
        print(f"  Đồng hồ trôi khi sạc đầy: {drift['lastPct']}% sau {drift.get('sessions')} lần sạc; "
              f"{drift['perFullPct']} điểm mỗi lần xả đầy")
    left = [f"{str(row.get('at'))[:10]} {row.get('reason')}" for row in result["charges"] if not row.get("used")]
    if left:
        print("  Không tính: " + ", ".join(left))


if __name__ == "__main__":
    main()
