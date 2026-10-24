"""Read battery % and ODO from a dashboard photo with Gemini (QA 135).

The phone's seven-segment reader is first; this is its fallback for glare,
unusual clusters or extreme angles. One cropped grayscale image per call,
sent through the existing Gemini relay; nothing is stored. The answer is
validated (0–100 %, ODO not below the last reading) and the owner still
checks it before saving.
"""
from __future__ import annotations

import base64
import binascii
import json
import re

MAX_IMAGE_BYTES = 380 * 1024  # the relay accepts 512 KB of JSON (base64)
_MIME = {"image/png": b"\x89PNG", "image/jpeg": b"\xff\xd8"}

PROMPT = (
    "The image shows the instrument cluster of a VinFast electric scooter, usually a "
    "seven-segment LCD. Read two values and answer with JSON only: "
    '{"soc": integer 0-100 or null, "odoKm": number or null, "confidence": number 0-1}. '
    "soc = battery percentage: the number next to the % sign or the battery icon "
    "(1, 2 or 3 digits). odoKm = total distance on the odometer: the number next to "
    "'ODO' or 'KM' (not KM/H), up to 6 digits; a gap inside it is still one number "
    "(\"48 18\" = 4818). Ignore the speed (KM/H, usually the largest digits), trip, "
    "clock and temperature (°C). If a value is not clearly readable, use null. Never guess."
)


class ScanError(RuntimeError):
    def __init__(self, code: str, message: str, status: int = 400):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


def decode_image(raw: str | None, mime: str | None) -> tuple[bytes, str]:
    mime = str(mime or "image/png").lower()
    if mime not in _MIME:
        raise ScanError("invalidImage", "Ảnh phải là PNG hoặc JPEG.")
    try:
        data = base64.b64decode(str(raw or ""), validate=True)
    except (binascii.Error, ValueError):
        raise ScanError("invalidImage", "Ảnh không hợp lệ.") from None
    if not data:
        raise ScanError("invalidImage", "Thiếu ảnh.")
    if len(data) > MAX_IMAGE_BYTES:
        raise ScanError("imageTooLarge", "Ảnh quá lớn.", 413)
    if not data.startswith(_MIME[mime]):
        raise ScanError("invalidImage", "Ảnh không đúng định dạng.")
    return data, mime


def parse_answer(text: str, last_odo_km: float | None = None) -> dict:
    """The model's JSON → validated values (anything odd becomes null)."""
    cleaned = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.IGNORECASE).strip()
    match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)
    try:
        data = json.loads(match.group(0) if match else cleaned)
    except (ValueError, TypeError):
        return {"soc": None, "odoKm": None, "confidence": 0.0}
    if not isinstance(data, dict):
        return {"soc": None, "odoKm": None, "confidence": 0.0}

    def number(value):
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            value = re.sub(r"(?i)km|%", "", value).strip()
            digits =re.sub(r"[\s.,](?=\d{3}\b)|\s", "", value)
            try:
                return float(digits)
            except ValueError:
                return None
        return None

    soc = number(data.get("soc"))
    soc = int(round(soc)) if soc is not None and 0 <= soc <= 100 and float(soc).is_integer() else None
    odo = number(data.get("odoKm"))
    if odo is not None and not 0 <= odo < 1_000_000:
        odo = None
    if odo is not None and last_odo_km is not None and odo < last_odo_km - 1:
        odo = None  # the odometer never goes back
    confidence = number(data.get("confidence"))
    confidence = max(0.0, min(1.0, confidence)) if confidence is not None else 0.5
    return {"soc": soc, "odoKm": odo, "confidence": round(confidence, 2)}


class DashboardImageReader:
    def __init__(self, gemini):
        self.gemini = gemini

    @property
    def configured(self) -> bool:
        return bool(getattr(self.gemini, "configured", False))

    def read(self, image: bytes, mime: str, last_odo_km: float | None = None) -> dict:
        hint = ""
        if last_odo_km is not None:
            hint = f" The previous odometer reading was {round(last_odo_km)} km; the new one is the same or larger."
        parts = self.gemini.generate(
            system=PROMPT,
            contents=[{"role": "user", "parts": [
                {"inlineData": {"mimeType": mime, "data": base64.b64encode(image).decode("ascii")}},
                {"text": "Read the battery % and the ODO." + hint},
            ]}],
            temperature=0.0, max_tokens=200, timeout=15, response_mime_type="application/json",
        )
        text = "".join(str(p.get("text") or "") for p in parts if "text" in p)
        return parse_answer(text, last_odo_km)
