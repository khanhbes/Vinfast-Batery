"""QA 158, tier 4: does the odometer help read the battery? LOCAL, READ ONLY.

Reads the file written by tools/read_charge_ledger.ps1 (charge-ledger.local.json)
and compares, for every charge that has the odometer at the previous charge's
end and at this one's start:

  gauge   = the % the owner read before charging
  ledger  = previous end % - km ridden / km per 1 % (the trip model)

The question is whether a mix of both predicts the end of the charge better than
the gauge alone. Run after at least 10 such charges:

    python web/scripts/qa158_cross_check.py [path/to/charge-ledger.local.json]

Prints a recommendation; nothing is written anywhere.
"""
from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path

MIN_CHARGES = 10


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")  # Windows consoles default to cp1252
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "charge-ledger.local.json")
    data = json.loads(path.read_text(encoding="utf-8"))
    learned = data.get("learned") or {}
    wh = learned.get("whPerPct")
    km_per_pct = ((data.get("trainingReports") or {}).get("trip") or {}).get("kmPerPct")
    if not wh or not km_per_pct:
        print("Thiếu Wh/1% hoặc km/1% đã học: chưa so được.")
        return 1
    charges = {item["sessionId"]: item for item in [*(learned.get("samples") or []),
                                                    *(learned.get("ledger") or [])]}
    rows = []
    for cross in learned.get("crossLog") or []:
        charge = charges.get(cross.get("sessionId"))
        if not charge or float(charge.get("actualEndPct") or 0) >= 99:
            continue
        ledger_start = float(cross["previousEndPct"]) - float(cross["km"]) / float(km_per_pct)
        gauge_start = float(cross["gaugeStartPct"])
        added = float(charge["energyWh"]) / float(wh)
        actual = float(charge["actualEndPct"])
        rows.append({"gauge": gauge_start + added - actual,
                     "ledger": ledger_start + added - actual,
                     "mix": (gauge_start + ledger_start) / 2 + added - actual,
                     "gap": gauge_start - ledger_start})
    print(f"Lần sạc có đủ ODO: {len(rows)} (cần {MIN_CHARGES})")
    if len(rows) < MIN_CHARGES:
        return 0

    def mae(key: str) -> float:
        return statistics.mean(abs(row[key]) for row in rows)

    gauge, ledger, mix = mae("gauge"), mae("ledger"), mae("mix")
    print(f"Sai số trung bình: chỉ đồng hồ {gauge:.2f}% · chỉ theo km {ledger:.2f}% · "
          f"trung bình hai số {mix:.2f}%")
    big = [row for row in rows if abs(row["gap"]) > 6]
    if big:
        flagged = statistics.mean(abs(row["gauge"]) for row in big)
        print(f"Khi hai số lệch nhau quá 6% ({len(big)} lần): đồng hồ sai trung bình {flagged:.2f}%")
    if mix < gauge * 0.9:
        print("Kết luận: ODO giúp giảm sai số rõ. Nên bật bước dùng ở tầng 4.")
    else:
        print("Kết luận: ODO không giúp rõ. Giữ chỉ thu thập, không bật.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
