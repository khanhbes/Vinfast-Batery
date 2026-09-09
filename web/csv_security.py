"""Safe CSV serialization for data opened in spreadsheet applications."""
from __future__ import annotations

import csv
import io
import json
from collections.abc import Iterable, Mapping
from typing import Any


_FORMULA_PREFIXES = ("=", "+", "-", "@")


def sanitize_csv_value(value: Any) -> Any:
    """Prevent untrusted text from being interpreted as a spreadsheet formula.

    Numeric values remain numeric. Only text whose first meaningful character is
    a formula marker (or a tab/carriage-return control) receives an apostrophe.
    """
    if isinstance(value, (dict, list, tuple)):
        value = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if not isinstance(value, str) or not value:
        return value

    candidate = value.lstrip(" \n")
    if candidate.startswith(_FORMULA_PREFIXES) or candidate.startswith(("\t", "\r")):
        return "'" + value
    return value


def csv_text(rows: Iterable[Mapping[str, Any]], fieldnames: Iterable[str] | None = None) -> str:
    """Serialize mappings as CSV with a stable union of columns and safe cells."""
    materialized = list(rows)
    if fieldnames is None:
        seen: set[str] = set()
        columns: list[str] = []
        for row in materialized:
            for key in row:
                if key not in seen:
                    seen.add(key)
                    columns.append(key)
    else:
        columns = list(fieldnames)

    if not columns:
        return ""

    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=columns, extrasaction="ignore")
    writer.writeheader()
    for row in materialized:
        writer.writerow({key: sanitize_csv_value(value) for key, value in row.items()})
    return output.getvalue()
