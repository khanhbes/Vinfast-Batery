"""QA 166: measure, on the owner's own charges, every error the battery
capacity carries, before deciding anything from it.

Read-only. Reads the files the owner's two scripts wrote (never committed):
`tools/read_charge_ledger.ps1` -> charge-ledger.local.json (the learned
charges) and, if present, `tools/read_charge_sessions.ps1` ->
charge-sessions.local.json (sessions with their 1-minute power curves).

    python web/scripts/qa166_capacity_study.py [charge-ledger.local.json] [charge-sessions.local.json]

Prints:
  1. the gauge error of each kind of charge (trust, where the start % came
     from, how it ended), with an 80 % bootstrap interval;
  2. whether a kind of charge reads high or low (start and end bands, how
     long after the charge the end % was typed, temperature): a correction is
     only worth making where the mean is beyond 2 standard errors;
  3. energy counted with the charger idle, and the charger's steady power;
  4. the charges from 0 % to 100 % (with their curves when there are);
  5. leave-one-out: each charge's Wh per 1 % predicted from the others, by
     the QA 162 weights and by the QA 166 ones.
"""
from __future__ import annotations

import json
import math
import random
import statistics
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from shelly import charge_model as cm  # noqa: E402

QA162_TRUST = {"high": 1.0, "medium": 0.35, "low": 0.1}


def _load(path: Path) -> tuple[list[dict], float]:
    data = json.loads(path.read_text(encoding="utf-8"))
    learned = data.get("learned") or {}
    merged: dict[str, dict] = {}
    for key in ("ledger", "samples", "pending"):
        for index, item in enumerate(learned.get(key) or []):
            merged[str(item.get("sessionId") or f"{key}{index}")] = item
    nominal = float((data.get("vehicle") or {}).get("nominalCapacityWh") or 0)
    return sorted(merged.values(), key=lambda item: str(item.get("at") or "")), nominal


def _rows(charges: list[dict]) -> list[dict]:
    """The battery_health rows with weights and each one's residual (in %
    points of the gauge) against its neighbours."""
    trusts = cm._health_trusts(charges)
    epochs, _ = cm._health_epochs(charges)
    rows = cm._charge_rows(charges, trusts, cm.DEFAULT_EFFICIENCY, lambda c: c, epochs)
    sigmas = cm.health_sigmas(rows)["points"]
    cm._apply_weights(rows, sigmas)
    eligible = [row for row in rows if row["weight"] > 0]
    for index, row in enumerate(eligible):
        near = [other for other in eligible[max(0, index - cm.HEALTH_NEIGHBOURS): index + cm.HEALTH_NEIGHBOURS + 1]
                if other is not row and other["epoch"] == row["epoch"]]
        weight = sum(other["weight"] for other in near)
        if len(near) >= 2 and weight > 0:
            centre = sum(other["weight"] * other["r"] for other in near) / weight
            row["residualRel"] = row["r"] / centre - 1
            row["residualPoints"] = row["residualRel"] * row["gain"]
    for row, item in zip(rows, charges):
        row["item"] = item
    return rows


def _rms(values: list[float]) -> float:
    return math.sqrt(sum(v * v for v in values) / len(values)) if values else float("nan")


def _bootstrap(values: list[float], rounds: int = 1000) -> tuple[float, float]:
    if len(values) < 2:
        return float("nan"), float("nan")
    rng = random.Random(166)
    stats = sorted(_rms([rng.choice(values) for _ in values]) for _ in range(rounds))
    return stats[int(rounds * 0.1)], stats[int(rounds * 0.9)]


def _group(rows: list[dict], name: str, key) -> None:
    groups: dict[str, list[float]] = {}
    for row in rows:
        if "residualPoints" in row:
            groups.setdefault(str(key(row)), []).append(row["residualPoints"])
    print(f"  theo {name}:")
    for label, values in sorted(groups.items()):
        low, high = _bootstrap(values)
        print(f"    {label:<16} {len(values):>3} lần  σ {_rms(values):5.2f} điểm  (80%: {low:.2f}–{high:.2f})")


def _band(rows: list[dict], name: str, key) -> None:
    groups: dict[str, list[float]] = {}
    for row in rows:
        if "residualRel" in row:
            label = key(row)
            if label is not None:
                groups.setdefault(label, []).append(row["residualRel"] * 100)
    print(f"  theo {name}:")
    for label, values in sorted(groups.items()):
        mean = statistics.mean(values)
        se = statistics.stdev(values) / math.sqrt(len(values)) if len(values) >= 2 else float("nan")
        flag = "  <- lệch rõ" if len(values) >= 3 and abs(mean) > 2 * se else ""
        print(f"    {label:<16} {len(values):>3} lần  lệch {mean:+6.2f}% ± {se:.2f}{flag}")


def _bucket(value, edges: list[float], labels: list[str]) -> str | None:
    if value is None:
        return None
    for edge, label in zip(edges, labels):
        if float(value) < edge:
            return label
    return labels[-1]


def _qa162_wh(charges: list[dict], now: datetime) -> float | None:
    """The QA 162 pooled Wh per 1 %: % gained x trust x age, test x2, robust outliers."""
    trusts = cm._health_trusts(charges)
    rows = []
    for item in charges:
        start = float(item.get("startPct") or 0)
        end = float(item.get("actualEndPct") or 0)
        gain = end - start
        energy = float(item.get("energyWh") or 0)
        if item.get("censored") and item.get("labelSource") != "taper_full":
            continue
        if gain < cm.HEALTH_MIN_GAIN_PCT or energy <= 0:
            continue
        at = cm._parse_at(item.get("at"))
        age = (now - at).total_seconds() / 86400 if at else 0.0
        if age > cm.HEALTH_WINDOW_DAYS:
            continue
        test = item.get("labelSource") == "taper_full" and start <= cm.HEALTH_TEST_MAX_START_PCT
        trust = "high" if test else trusts.get(str(item.get("sessionId") or ""), "low")
        weight = gain * QA162_TRUST[trust] * 0.5 ** (max(0.0, age) / 180)
        if test and age <= 90:
            weight *= 2
        rows.append((energy / gain, weight, energy, gain))
    rows = rows[-cm.HEALTH_WINDOW_CHARGES:]
    if not rows:
        return None
    if len(rows) >= 3:
        middle = cm._weighted_median([(r, w) for r, w, _, _ in rows])
        mad = cm._weighted_median([(abs(r - middle), w) for r, w, _, _ in rows])
        limit = max(3 * 1.4826 * mad, middle * cm.HEALTH_OUTLIER_FLOOR_PCT / 100)
        rows = [row for row in rows if abs(row[0] - middle) <= limit] or rows
    return sum(w * e for _, w, e, _ in rows) / sum(w * g for _, w, _, g in rows)


def _qa166_wh(charges: list[dict], now: datetime) -> float | None:
    result = cm.battery_health(charges, 2400, history=charges, now=now)
    estimate = result["estimate"]
    if not estimate:
        return None
    return estimate["capacityWh"] / 100 / cm.DEFAULT_EFFICIENCY


def _leave_one_out(charges: list[dict], rows: list[dict]) -> None:
    now = (cm._parse_at(charges[-1].get("at")) or datetime.now(timezone.utc)) + timedelta(hours=1)
    # Each charge keeps the trust it had: leaving one out must not move the
    # next one to "right after a full charge".
    trusts = cm._health_trusts(charges)
    charges = [{**item, "trust": trusts.get(str(item.get("sessionId") or ""), "low")} for item in charges]
    errors: dict[str, dict[str, list[float]]] = {}
    for index, row in enumerate(rows):
        if row["weight"] <= 0:
            continue
        others = charges[:index] + charges[index + 1:]
        for name, fn in (("QA 162", _qa162_wh), ("QA 166", _qa166_wh)):
            wh = fn(others, now)
            if wh:
                errors.setdefault(row["trust"], {}).setdefault(name, []).append((wh / row["r"] - 1) * 100)
    for trust in ("high", "medium", "low"):
        by = errors.get(trust)
        if not by:
            continue
        parts = [f"{name}: RMSE {_rms(values):.2f}% ({len(values)} lần)" for name, values in sorted(by.items())]
        print(f"  tin {trust:<6} " + " · ".join(parts))


def _sessions(path: Path | None) -> dict[str, dict]:
    if path is None or not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {str(item.get("session_id")): item for item in data.get("sessions") or []}


def _curve(session: dict) -> list[dict]:
    return [{"t": t, "p": p, "wh": wh} for t, p, wh in (session.get("curve") or [])]


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    ledger = Path(sys.argv[1] if len(sys.argv) > 1 else "charge-ledger.local.json")
    sessions = _sessions(Path(sys.argv[2]) if len(sys.argv) > 2 else Path("charge-sessions.local.json"))
    charges, nominal = _load(ledger)
    if not charges or nominal <= 0:
        print("Không có lần sạc hoặc dung lượng danh định.")
        return
    rows = _rows(charges)
    counted = [row for row in rows if "residualPoints" in row]
    print(f"{len(charges)} lần sạc, {sum(1 for r in rows if r['weight'] > 0)} lần tính được, "
          f"{len(counted)} lần có lần sạc lân cận để so; {len(sessions)} phiên có đường công suất\n")

    print("1. Sai số đồng hồ (điểm %, so với các lần sạc quanh nó):")
    _group(counted, "độ tin (QA 158)", lambda row: row["trust"])
    _group(counted, "nguồn % đầu", lambda row: row["item"].get("startSource") or "chưa ghi")
    _group(counted, "cách kết thúc", lambda row: "bộ sạc báo đầy" if row["fullEnd"] else "nhập % cuối")
    learned = cm.health_sigmas(rows)
    print("  app đang dùng: " + ", ".join(f"{k} {v:.2f}" for k, v in learned["points"].items()))

    print("\n2. Lệch có hệ thống (chỉ sửa khi vượt 2 sai số chuẩn):")
    _band(counted, "% đầu", lambda row: _bucket(row["item"].get("startPct"), [10, 30, 60], ["0–10", "10–30", "30–60", "≥ 60"]))
    _band(counted, "% cuối", lambda row: ("đầy" if row["fullEnd"] else
                                         _bucket(row["item"].get("actualEndPct"), [70, 90, 99], ["< 70", "70–90", "90–99", "≥ 99"])))
    _band(counted, "nhập % cuối sau", lambda row: _bucket(row["item"].get("endAfterMin"), [30, 360],
                                                           ["< 30 phút", "30 phút–6 giờ", "> 6 giờ"]))
    _band(counted, "nhiệt độ pin", lambda row: _bucket(row["item"].get("batteryTempC"), [25, 35], ["< 25 °C", "25–35 °C", "≥ 35 °C"]))

    print("\n3. Điện lúc bộ sạc không sạc và công suất ổn định:")
    idle, plateaus = [], []
    for item in charges:
        session = sessions.get(str(item.get("sessionId") or ""))
        curve = _curve(session) if session else []
        tail = item.get("tailWh")
        if tail is None and curve:
            tail = cm.idle_energy_wh(curve, session.get("energy_used_wh"))
        plateau = item.get("plateauW") or (cm.plateau_power_w(curve) if curve else None) or item.get("avgPowerW")
        if tail is not None and item.get("energyWh"):
            idle.append(100 * float(tail) / float(item["energyWh"]))
        if plateau:
            plateaus.append(float(plateau))
    if idle:
        print(f"  điện lúc chờ: trung bình {statistics.mean(idle):.3f}% điện của lần sạc, lớn nhất {max(idle):.3f}% ({len(idle)} lần)")
    else:
        print("  điện lúc chờ: chưa có số đo (cần bản ghi công suất)")
    if plateaus:
        spread = statistics.pstdev(plateaus) / statistics.mean(plateaus) * 100
        print(f"  công suất ổn định: {min(plateaus):.0f}–{max(plateaus):.0f} W, lệch chuẩn {spread:.1f}% ({len(plateaus)} lần)")

    print("\n4. Các lần sạc từ khoảng 0% tới 100%:")
    for item in charges:
        start = item.get("startPct")
        if start is None or float(start) > 2 or float(item.get("actualEndPct") or 0) < 99:
            continue
        line = (f"  {str(item.get('at'))[:16]}  {item.get('startPct'):.0f}→{item.get('actualEndPct'):.0f}%  "
                f"{float(item.get('energyWh') or 0):.0f} Wh  {float(item.get('whPerPct') or 0):.2f} Wh/1%  "
                f"kết thúc: {item.get('labelSource')}  nguồn % đầu: {item.get('startSource') or 'chưa ghi'}")
        print(line)
        session = sessions.get(str(item.get("sessionId") or ""))
        if session and session.get("curve"):
            curve = _curve(session)
            powers = [c["p"] for c in curve]
            minutes = (curve[-1]["t"] - curve[0]["t"]) / 60 if len(curve) > 1 else 0
            under_tail = sum(max(0.0, b["wh"] - a["wh"]) for a, b in zip(curve, curve[1:])
                             if a["p"] < cm.FULL_TAIL_W and b["p"] < cm.FULL_TAIL_W)
            print(f"      {minutes:.0f} phút, công suất cao nhất {max(powers):.0f} W, cuối {powers[-1]:.0f} W, "
                  f"dưới {cm.FULL_TAIL_W:.0f} W: {under_tail:.1f} Wh, ngắt vì {session.get('stop_reason')}")
        elif sessions:
            print("      (không có bản ghi công suất của phiên này)")

    print("\n5. Dự đoán từng lần sạc từ các lần còn lại (sai số Wh/1%):")
    _leave_one_out(charges, rows)

    _drift_check(charges)


def _drift_check(charges: list[dict]) -> None:
    """QA 166 (2): with the pooled Wh per 1 %, a charge stopped midway should
    gain on the gauge what its energy says (the drift cancels), and a charge
    to the charger's full signal shows how far the gauge had drifted at its
    start. On 18/11/2026 the owner's two charges to full started 13.6 and
    14.0 points above the gauge, the charges right after a full one within
    1.1 points: the gauge drifts low between full charges."""
    now = max(cm._parse_at(item.get("at")) or datetime.now(timezone.utc) for item in charges)
    wh = _qa166_wh(charges, now + timedelta(hours=1))
    if not wh:
        return
    print(f"\n6. Đồng hồ trôi (lấy {wh:.2f} Wh/1% gộp):")
    for item in charges:
        energy = float(item.get("energyWh") or 0)
        start = item.get("startPct")
        if not energy or start is None:
            continue
        gained = energy / wh
        when = str(item.get("at"))[:10]
        if item.get("labelSource") == "taper_full":
            true_start = 100 - gained
            print(f"  {when} {float(start):5.1f} → đầy   pin thật lúc cắm {true_start:5.1f}% "
                  f"(đồng hồ lệch {float(start) - true_start:+.1f})  tin {item.get('trust') or '?'}")
        elif item.get("actualEndPct") is not None and not item.get("censored"):
            shown = float(item["actualEndPct"]) - float(start)
            print(f"  {when} {float(start):5.1f} → {float(item['actualEndPct']):5.1f}  đồng hồ +{shown:4.1f}  "
                  f"điện +{gained:5.1f}  chênh {shown - gained:+5.1f}  tin {item.get('trust') or '?'}")


if __name__ == "__main__":
    main()
