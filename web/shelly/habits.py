"""Charging habits and the "Đánh giá tổng quát" (QA 140, items 1 and 9).

Pure functions over finished sessions: the numbers behind the charts, a
score with plain comments built only from those numbers (nothing invented),
and a suggested schedule the owner may apply. The scooter reports no cell
data: every % here is the app's estimate or the owner's reading.
"""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta, timezone

VN = timezone(timedelta(hours=7))
WINDOW_DAYS = 60
MIN_SESSIONS = 3
MIN_ENERGY_WH = 30  # below: plugged in and out, not a charge
FULL_PCT = 95
LOW_PCT = 15
GOOD_TOP_PCT = 90
TERMINAL = {"completed", "interrupted", "cancelled", "stopped"}


def _end_pct(session) -> float | None:
    for value in (session.actual_end_soc, session.estimated_soc):
        if value is not None:
            return max(0.0, min(100.0, float(value)))
    return None


def _usable(session) -> bool:
    return (session.state in TERMINAL and session.hidden_at is None
            and float(session.energy_used_wh or 0) >= MIN_ENERGY_WH
            and session.stopped_at is not None)


def charge_habits(sessions, *, now: datetime, wh_per_pct: float | None = None,
                  power_w: float | None = None) -> dict:
    """Stats, charts, score, comments and a schedule from [sessions]."""
    since = now - timedelta(days=WINDOW_DAYS)
    rows = []
    for s in sessions:
        start = s.relay_on_at or s.created_at
        if not _usable(s) or start < since:
            continue
        end_pct = _end_pct(s)
        rows.append({
            "start": start.astimezone(VN),
            "end": s.stopped_at.astimezone(VN),
            "startPct": max(0.0, min(100.0, float(s.start_soc))),
            "endPct": end_pct,
            "energyWh": float(s.energy_used_wh or 0),
            "full": s.stop_reason == "battery_full" or (end_pct is not None and end_pct >= FULL_PCT),
            "tempC": s.shelly_temperature_c,
            "confirmed": s.actual_end_soc is not None,
        })
    rows.sort(key=lambda r: r["start"])
    result = {
        "windowDays": WINDOW_DAYS, "sessions": len(rows),
        "enough": len(rows) >= MIN_SESSIONS, "minSessions": MIN_SESSIONS,
        "stats": None, "charts": None, "score": None, "comments": [], "suggestions": [],
        "schedule": None,
    }
    if not rows:
        return result

    n = len(rows)
    weeks = max(1.0, (now - rows[0]["start"].astimezone(timezone.utc)).days / 7) if n > 1 else 1.0
    ends = [r["endPct"] for r in rows if r["endPct"] is not None]
    depths = [r["endPct"] - r["startPct"] for r in rows if r["endPct"] is not None]
    full = sum(1 for r in rows if r["full"])
    low = sum(1 for r in rows if r["startPct"] < LOW_PCT)
    night = sum(1 for r in rows if r["start"].hour >= 22 or r["start"].hour < 6)
    temps = [float(r["tempC"]) for r in rows if r["tempC"] is not None]
    stats = {
        "perWeek": round(n / weeks, 1),
        "avgStartPct": round(sum(r["startPct"] for r in rows) / n),
        "avgEndPct": round(sum(ends) / len(ends)) if ends else None,
        "avgDepthPct": round(sum(depths) / len(depths)) if depths else None,
        "equivalentCycles": round(sum(max(0.0, d) for d in depths) / 100, 1),
        "fullShare": round(full / n, 2),
        "lowStartShare": round(low / n, 2),
        "nightShare": round(night / n, 2),
        "maxOutletTempC": round(max(temps)) if temps else None,
        "kWh": round(sum(r["energyWh"] for r in rows) / 1000, 2),
        "confirmedShare": round(sum(1 for r in rows if r["confirmed"]) / n, 2),
    }
    result["stats"] = stats

    # Charts: start hour × weekday, start/end % spread, kWh per week.
    heat = [[0] * 24 for _ in range(7)]
    for r in rows:
        heat[r["start"].weekday()][r["start"].hour] += 1
    def bucket(value):
        return min(9, int(value // 10))
    starts, end_hist = [0] * 10, [0] * 10
    for r in rows:
        starts[bucket(r["startPct"])] += 1
        if r["endPct"] is not None:
            end_hist[bucket(r["endPct"])] += 1
    week_kwh = Counter()
    for r in rows:
        monday = (r["start"] - timedelta(days=r["start"].weekday())).date()
        week_kwh[monday.isoformat()] += r["energyWh"] / 1000
    result["charts"] = {
        "weekdayHour": heat,
        "startPct": starts, "endPct": end_hist,
        "weeklyKWh": [{"week": k, "kWh": round(v, 2)} for k, v in sorted(week_kwh.items())][-8:],
    }

    if not result["enough"]:
        return result

    # Score: 100, minus what wears an LFP/NMC pack or the outlet.
    score = 100
    comments, suggestions = [], []
    if stats["fullShare"] > 0.5:
        score -= 25
        comments.append({"level": "warn", "text":
            f"{round(stats['fullShare'] * 100)}% số lần sạc lên gần 100%. Giữ pin đầy lâu làm pin chai nhanh hơn."})
        suggestions.append("Hằng ngày dừng ở 80–90%; chỉ sạc đầy trước chuyến đi xa.")
    elif stats["fullShare"] > 0.25:
        score -= 8
        comments.append({"level": "info", "text":
            f"{round(stats['fullShare'] * 100)}% số lần sạc lên gần 100%: được, nhưng nên ít hơn."})
    else:
        comments.append({"level": "good", "text": "Ít khi sạc tới 100%, tốt cho tuổi thọ pin."})
    if stats["lowStartShare"] > 0.3:
        score -= 25
        comments.append({"level": "warn", "text":
            f"{round(stats['lowStartShare'] * 100)}% số lần bắt đầu sạc khi pin dưới {LOW_PCT}%. Xả sâu thường xuyên hại pin."})
        suggestions.append(f"Cắm sạc khi pin còn khoảng 20–30%, tránh để dưới {LOW_PCT}%.")
    elif stats["lowStartShare"] > 0.1:
        score -= 8
        comments.append({"level": "info", "text":
            f"Thỉnh thoảng ({round(stats['lowStartShare'] * 100)}%) để pin xuống dưới {LOW_PCT}% mới sạc."})
    else:
        comments.append({"level": "good", "text": f"Hầu như không để pin xuống dưới {LOW_PCT}%."})
    if stats["perWeek"] > 7:
        score -= 5
        comments.append({"level": "info", "text":
            f"Sạc khoảng {stats['perWeek']} lần mỗi tuần: nhiều lần ngắn vẫn ổn, không cần cắm sau mỗi chuyến."})
    if stats["maxOutletTempC"] is not None and stats["maxOutletTempC"] >= 60:
        score -= 15
        comments.append({"level": "warn", "text":
            f"Ổ Shelly từng nóng tới {stats['maxOutletTempC']} °C khi sạc. Kiểm tra phích cắm và chỗ đặt ổ cho thoáng."})
        suggestions.append("Đặt ổ ở nơi thoáng, không phủ vật gì lên; sạc lúc mát trời nếu có thể.")
    if stats["confirmedShare"] < 0.3:
        suggestions.append("Sau mỗi lần sạc, nhập % trên đồng hồ xe để đánh giá chính xác hơn.")
    result["score"] = max(0, min(100, score))
    result["grade"] = "good" if score >= 80 else "fair" if score >= 60 else "poor"
    result["comments"] = comments
    result["suggestions"] = suggestions
    result["schedule"] = suggest_schedule(rows, wh_per_pct=wh_per_pct, power_w=power_w)
    return result


def suggest_schedule(rows, *, wh_per_pct: float | None, power_w: float | None) -> dict | None:
    """When the owner usually plugs in, and a battery-friendly plan for it:
    start at that hour, stop at 85% (90% if they often need more)."""
    if len(rows) < MIN_SESSIONS:
        return None
    hours = Counter(r["start"].hour for r in rows)
    hour, count = hours.most_common(1)[0]
    days = Counter(r["start"].weekday() for r in rows if r["start"].hour == hour)
    weekdays = sorted(d for d, c in days.items() if c >= 1)
    starts = sorted(r["startPct"] for r in rows if r["start"].hour == hour)
    typical_start = starts[len(starts) // 2]
    ends = [r["endPct"] for r in rows if r["endPct"] is not None]
    target = 90 if ends and sum(1 for e in ends if e >= FULL_PCT) / len(ends) > 0.6 else 85
    minutes = None
    if wh_per_pct and power_w and power_w > 0 and target > typical_start:
        minutes = round((target - typical_start) * wh_per_pct / power_w * 60)
    return {
        "startHour": hour, "weekdays": weekdays, "share": round(count / len(rows), 2),
        "typicalStartPct": round(typical_start), "targetPct": target,
        "estimatedMinutes": minutes,
    }
