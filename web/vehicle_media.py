"""Vehicle catalog media: storage backends, image processing and showroom schema.

Official photos are uploaded by an administrator (rights confirmed, credited).
Images keep their alpha channel; studio shots on a white/light-grey background
can have that background removed so the vehicle sits on the app's dark stage.

``media.showroom`` describes colours and, per colour, an ordered list of angle
images. The mobile app shows a 2.5D stage for any colour and enables a 360°
drag when a colour has at least ``SPIN_MIN_ANGLES`` angles.
"""

from __future__ import annotations

import hashlib
import os
import re
import uuid
from datetime import datetime, timezone
from io import BytesIO
from typing import Any, Protocol

try:
    import numpy as np
except Exception:  # pragma: no cover - numpy ships with the API image.
    np = None

try:
    from PIL import Image, ImageFilter, ImageOps
except Exception:  # pragma: no cover
    Image = None
    ImageFilter = None
    ImageOps = None

try:
    from scipy import ndimage
except Exception:  # pragma: no cover - scipy ships with scikit-learn in the API image.
    ndimage = None

MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_COLORS = 8
MAX_ANGLES = 36
SPIN_MIN_ANGLES = 12
SIZES = ((320, "thumbnail"), (768, "medium"), (1280, "hero"))
CANVAS_RATIO = 16 / 10
ASSET_KEYS = (
    "thumbnailUrl", "mediumUrl", "heroUrl", "sourceUrl", "credit", "licenseNote",
    "checksum", "approvedAt", "kind", "backgroundRemoved", "width", "height",
)
_HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
_COLOR_ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def _text(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


# ─────────────────────────────── Storage ───────────────────────────────


class MediaStore(Protocol):
    def put(self, path: str, data: bytes, content_type: str) -> str: ...

    def owns(self, url: str) -> bool: ...


class AzureBlobMediaStore:
    """Public-read container; the API writes with its managed identity."""

    def __init__(self, account: str, container: str, client_id: str | None = None):
        if not re.fullmatch(r"[a-z0-9]{3,24}", account):
            raise ValueError("Invalid storage account name")
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])", container):
            raise ValueError("Invalid container name")
        self.account = account
        self.container = container
        self.client_id = client_id
        self._client = None

    @property
    def base_url(self) -> str:
        return f"https://{self.account}.blob.core.windows.net/{self.container}/"

    def _container(self):
        if self._client is None:
            from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
            from azure.storage.blob import BlobServiceClient

            credential = (
                ManagedIdentityCredential(client_id=self.client_id)
                if self.client_id
                else DefaultAzureCredential(exclude_interactive_browser_credential=True)
            )
            service = BlobServiceClient(
                f"https://{self.account}.blob.core.windows.net", credential=credential
            )
            self._client = service.get_container_client(self.container)
        return self._client

    def put(self, path: str, data: bytes, content_type: str) -> str:
        from azure.storage.blob import ContentSettings

        self._container().upload_blob(
            name=path,
            data=data,
            overwrite=True,
            content_settings=ContentSettings(
                content_type=content_type,
                # Paths embed the content checksum, so they never change.
                cache_control="public, max-age=31536000, immutable",
            ),
        )
        return self.base_url + path

    def owns(self, url: str) -> bool:
        return isinstance(url, str) and url.startswith(self.base_url)


class FirebaseMediaStore:
    """Legacy backend (requires a Firebase Storage bucket)."""

    def put(self, path: str, data: bytes, content_type: str) -> str:
        from firebase_admin import storage

        bucket = storage.bucket()
        blob = bucket.blob(path)
        token = str(uuid.uuid4())
        blob.metadata = {"firebaseStorageDownloadTokens": token}
        blob.upload_from_string(data, content_type=content_type)
        return (
            f"https://firebasestorage.googleapis.com/v0/b/{bucket.name}/o/"
            f"{path.replace('/', '%2F')}?alt=media&token={token}"
        )

    def owns(self, url: str) -> bool:
        return isinstance(url, str) and url.startswith("https://firebasestorage.googleapis.com/")


def media_store_from_env() -> MediaStore:
    account = os.environ.get("VEHICLE_MEDIA_ACCOUNT", "").strip()
    if account:
        return AzureBlobMediaStore(
            account,
            os.environ.get("VEHICLE_MEDIA_CONTAINER", "vehicle-media").strip() or "vehicle-media",
            os.environ.get("AZURE_CLIENT_ID", "").strip() or None,
        )
    return FirebaseMediaStore()


# ─────────────────────────────── Image processing ───────────────────────────────


def _background_candidates(rgb: Any) -> Any:
    """Near-white / light-grey, low-chroma pixels (studio backdrop)."""
    lo = rgb.min(axis=2).astype(np.int16)
    hi = rgb.max(axis=2).astype(np.int16)
    return (lo >= 222) & ((hi - lo) <= 22)


def _flood_from_border(candidates: Any) -> Any:
    """Candidate pixels connected to the image border (4-connectivity)."""
    reached = np.zeros_like(candidates)
    reached[0, :] = candidates[0, :]
    reached[-1, :] = candidates[-1, :]
    reached[:, 0] = candidates[:, 0]
    reached[:, -1] = candidates[:, -1]
    for _ in range(candidates.shape[0] + candidates.shape[1]):
        grown = reached.copy()
        grown[1:, :] |= reached[:-1, :]
        grown[:-1, :] |= reached[1:, :]
        grown[:, 1:] |= reached[:, :-1]
        grown[:, :-1] |= reached[:, 1:]
        grown &= candidates
        if np.array_equal(grown, reached):
            break
        reached = grown
    return reached


def remove_light_background(image: Any) -> tuple[Any, bool]:
    """Return an RGBA image with a light studio backdrop (and its floor shadow) removed.

    The backdrop colour is estimated from the border, so pale vehicles (mint,
    pearl white) keep their body: only pixels close to *that* colour and
    connected to the border are cleared. The soft floor shadow is the backdrop
    darkened without changing tint; it is cleared only in the band just above
    the lowest part of the subject. Edges get a short soft matte and the
    backdrop tint is unmixed so no light halo shows on the app's dark stage.
    Enclosed areas (wheel windows, white logos) are kept on purpose: the
    floor seen through spokes has the same grey as silver discs and forks.
    Photos whose border is not a light backdrop are returned unchanged.
    """
    if np is None or Image is None:
        return image.convert("RGBA"), False
    if ndimage is None:
        return _remove_light_background_basic(image)
    rgba = image.convert("RGBA")
    rgb = np.asarray(rgba.convert("RGB")).astype(np.float32)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    backdrop = np.median(border, axis=0)
    border_dist = np.abs(border - backdrop).max(axis=1)
    if float(backdrop.min()) < 200 or float(np.mean(border_dist <= 18)) < 0.7:
        return rgba, False
    tol = float(np.clip(np.percentile(border_dist, 90) + 6, 6, 24))
    dist = np.abs(rgb - backdrop).max(axis=2)

    # 1) Backdrop: near-backdrop pixels connected to the border.
    labels, _ = ndimage.label(dist <= tol)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    background = np.isin(labels, edge[edge > 0])

    # 2) Floor shadow: backdrop scaled darker (same tint), smooth, near the ground.
    shade = rgb.mean(axis=2) / float(backdrop.mean())
    tint_dev = np.abs(rgb - shade[..., None] * backdrop).max(axis=2)
    solid = ~background & ((shade < 0.42) | (tint_dev > 9))
    rows = np.flatnonzero(solid.any(axis=1))
    shadow = np.zeros_like(background)
    if rows.size:
        top, bottom = int(rows[0]), int(rows[-1])
        band_top = int(bottom - 0.2 * (bottom - top))
        grad_y, grad_x = np.gradient(ndimage.gaussian_filter(rgb.mean(axis=2), 1.0))
        smooth = np.hypot(grad_x, grad_y) <= 8.0
        candidates = ~background & (shade >= 0.42) & (shade < 1.0) & (tint_dev <= 9) & smooth
        candidates[:band_top] = False
        grown, _ = ndimage.label(candidates | background)
        keep = np.unique(grown[background])
        shadow = np.isin(grown, keep[keep > 0]) & ~background
        if shadow.any():
            # Grey transition pixels between subject and shadow would leave a light rim.
            rim = ndimage.binary_dilation(shadow, iterations=3) & ~background & ~shadow
            rim &= (shade >= 0.35) & (tint_dev <= 12)
            rim[:band_top] = False
            shadow |= rim
    clear = background | shadow

    # 3) Soft matte on a thin edge band, then unmix the backdrop tint.
    band = ndimage.binary_dilation(clear, iterations=2) & ~clear
    alpha = np.where(clear, 0.0, 1.0)
    alpha[band] = np.clip((dist[band] - tol) / 30.0, 0.0, 1.0)
    alpha = ndimage.gaussian_filter(alpha, 0.6)
    alpha[clear] = 0.0  # softness comes from the subject side only, never a backdrop halo
    safe = np.clip(alpha, 1e-3, 1.0)[..., None]
    unmixed = np.clip((rgb - (1.0 - safe) * backdrop) / safe, 0, 255)
    colour = np.where(alpha[..., None] > 0.02, unmixed, rgb)
    out = np.dstack([colour, alpha * 255.0]).round().astype(np.uint8)
    # Keep the original alpha where the source already had transparency.
    out[..., 3] = np.minimum(out[..., 3], np.asarray(rgba.getchannel("A")))
    return Image.fromarray(out, "RGBA"), True


def _remove_light_background_basic(image: Any) -> tuple[Any, bool]:
    """Fallback without scipy: border flood fill over near-white pixels."""
    rgba = image.convert("RGBA")
    rgb = np.asarray(rgba.convert("RGB"))
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    lo = border.min(axis=1).astype(np.int16)
    hi = border.max(axis=1).astype(np.int16)
    if float(np.mean((lo >= 222) & ((hi - lo) <= 22))) < 0.7:
        return rgba, False

    small_w = min(320, rgba.width)
    small_h = max(1, round(rgba.height * small_w / rgba.width))
    small = np.asarray(rgba.convert("RGB").resize((small_w, small_h), Image.Resampling.BILINEAR))
    bg_small = _flood_from_border(_background_candidates(small))
    # Grow by one cell so the upscaled mask covers anti-aliased edges.
    grown = bg_small.copy()
    grown[1:, :] |= bg_small[:-1, :]
    grown[:-1, :] |= bg_small[1:, :]
    grown[:, 1:] |= bg_small[:, :-1]
    grown[:, :-1] |= bg_small[:, 1:]
    mask_up = Image.fromarray((grown * 255).astype(np.uint8)).resize(
        (rgba.width, rgba.height), Image.Resampling.NEAREST
    )
    background = (np.asarray(mask_up) > 0) & _background_candidates(rgb)
    alpha = np.where(background, 0, 255).astype(np.uint8)
    alpha_img = Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(radius=1.2))
    combined = np.minimum(np.asarray(alpha_img), np.asarray(rgba.getchannel("A")))
    rgba.putalpha(Image.fromarray(combined.astype(np.uint8)))
    return rgba, True


def frame_on_canvas(image: Any, *, crop: bool) -> Any:
    """Place the subject on a transparent 16:10 canvas.

    ``crop`` trims to the visible subject with an even margin (single images).
    Angle sequences pass ``crop=False`` so every frame keeps the same framing
    and the 360° spin does not jitter.
    """
    rgba = image.convert("RGBA")
    if crop:
        box = rgba.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
        if box:
            rgba = rgba.crop(box)
            pad = round(max(rgba.width, rgba.height) * 0.06)
            padded = Image.new("RGBA", (rgba.width + 2 * pad, rgba.height + 2 * pad), (0, 0, 0, 0))
            padded.paste(rgba, (pad, pad))
            rgba = padded
    width, height = rgba.size
    if width / height > CANVAS_RATIO:
        canvas = Image.new("RGBA", (width, round(width / CANVAS_RATIO)), (0, 0, 0, 0))
    else:
        canvas = Image.new("RGBA", (round(height * CANVAS_RATIO), height), (0, 0, 0, 0))
    # Subject rests on the lower part of the frame, like on a stage.
    x = (canvas.width - width) // 2
    y = canvas.height - height if crop else (canvas.height - height) // 2
    canvas.paste(rgba, (x, y), rgba)
    return canvas


def process_vehicle_image(
    content: bytes,
    *,
    remove_background: bool = True,
    crop: bool = True,
) -> tuple[list[tuple[str, int, bytes]], dict[str, Any]]:
    """Decode, optionally remove the backdrop, frame and encode WebP sizes."""
    if Image is None:
        raise ValueError("Image processing is unavailable")
    if len(content) > MAX_UPLOAD_BYTES:
        raise ValueError("Image exceeds 10 MB")
    try:
        image = Image.open(BytesIO(content))
        image = ImageOps.exif_transpose(image)
        image.load()
    except Exception as exc:
        raise ValueError("Unsupported or corrupted image") from exc
    if max(image.size) > 8000:
        raise ValueError("Image dimensions are too large")
    # Work at most at 2× the largest output to keep processing fast.
    if max(image.size) > 2560:
        scale = 2560 / max(image.size)
        image = image.resize(
            (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
            Image.Resampling.LANCZOS,
        )
    removed = False
    if remove_background:
        image, removed = remove_light_background(image)
    framed = frame_on_canvas(image, crop=crop and removed)
    outputs: list[tuple[str, int, bytes]] = []
    for width, label in SIZES:
        resized = framed
        if resized.width > width:
            resized = framed.resize(
                (width, max(1, round(framed.height * width / framed.width))),
                Image.Resampling.LANCZOS,
            )
        buffer = BytesIO()
        resized.save(buffer, "WEBP", quality=86, alpha_quality=92, method=6)
        outputs.append((label, resized.width, buffer.getvalue()))
    return outputs, {"backgroundRemoved": removed, "width": framed.width, "height": framed.height}


def store_vehicle_image(
    store: MediaStore,
    catalog_id: str,
    content: bytes,
    *,
    media_kind: str,
    source_url: str,
    credit: str,
    license_note: str,
    remove_background: bool = True,
    crop: bool = True,
    subpath: str = "",
) -> dict[str, Any]:
    outputs, info = process_vehicle_image(
        content, remove_background=remove_background, crop=crop
    )
    checksum = hashlib.sha256(content).hexdigest()
    prefix = f"vehicle-catalog/{catalog_id}/{media_kind}/{subpath + '/' if subpath else ''}{checksum[:12]}"
    urls = {
        label: store.put(f"{prefix}/{label}.webp", data, "image/webp")
        for label, _, data in outputs
    }
    return {
        "thumbnailUrl": urls["thumbnail"],
        "mediumUrl": urls["medium"],
        "heroUrl": urls["hero"],
        "sourceUrl": source_url,
        "credit": credit,
        "licenseNote": license_note,
        "checksum": checksum,
        "kind": media_kind,
        "approvedAt": utcnow(),
        **info,
    }


# ─────────────────────────────── Showroom schema ───────────────────────────────


def _https(value: Any) -> str:
    text = _text(value, 1200)
    return text if text.startswith("https://") else ""


def sanitize_asset(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    asset: dict[str, Any] = {}
    for key in ASSET_KEYS:
        if key not in raw:
            continue
        value = raw[key]
        if key.endswith("Url") and key != "sourceUrl":
            value = _https(value)
            if not value:
                continue
        elif key == "backgroundRemoved":
            value = bool(value)
        elif key in {"width", "height"}:
            try:
                value = max(0, min(20000, int(value)))
            except (TypeError, ValueError):
                continue
        else:
            value = _text(value, 1200)
        asset[key] = value
    return asset if asset.get("heroUrl") or asset.get("thumbnailUrl") else None


def sanitize_color(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    color_id = _text(raw.get("id"), 40).lower()
    if not _COLOR_ID.fullmatch(color_id):
        return None
    swatch = _text(raw.get("swatchHex"), 7)
    angles = [a for a in (sanitize_asset(x) for x in raw.get("angles") or []) if a]
    return {
        "id": color_id,
        "name": _text(raw.get("name"), 60) or color_id,
        "swatchHex": swatch.upper() if _HEX.fullmatch(swatch) else "#C9CDD2",
        "angles": angles[:MAX_ANGLES],
    }


def sanitize_showroom(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    colors: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw.get("colors") or []:
        color = sanitize_color(item)
        if color and color["id"] not in seen:
            seen.add(color["id"])
            colors.append(color)
        if len(colors) == MAX_COLORS:
            break
    if not colors:
        return None
    default = _text(raw.get("defaultColorId"), 40).lower()
    if default not in seen:
        default = colors[0]["id"]
    return {"defaultColorId": default, "colors": colors}


def refresh_primary(media: dict[str, Any]) -> dict[str, Any]:
    """Primary image = first angle of the default colour, else 2D, else 3D."""
    showroom = media.get("showroom") if isinstance(media.get("showroom"), dict) else None
    primary = None
    if showroom:
        color = next(
            (c for c in showroom["colors"] if c["id"] == showroom["defaultColorId"]), None
        )
        if color and color["angles"]:
            primary = color["angles"][0]
    views = media.get("views") if isinstance(media.get("views"), dict) else {}
    primary = primary or views.get("twoD") or views.get("threeD")
    keys = ("thumbnailUrl", "mediumUrl", "heroUrl", "sourceUrl", "credit",
            "licenseNote", "checksum", "approvedAt")
    for key in keys:
        if primary and key in primary:
            media[key] = primary[key]
        elif not primary:
            media.pop(key, None)
    return media


def add_showroom_angle(
    media: dict[str, Any],
    *,
    color_id: str,
    color_name: str,
    swatch_hex: str,
    angle_index: int | None,
    asset: dict[str, Any],
) -> dict[str, Any]:
    media = dict(media or {})
    showroom = sanitize_showroom(media.get("showroom")) or {"defaultColorId": "", "colors": []}
    color = next((c for c in showroom["colors"] if c["id"] == color_id), None)
    if color is None:
        if len(showroom["colors"]) >= MAX_COLORS:
            raise ValueError(f"At most {MAX_COLORS} colours per vehicle")
        color = sanitize_color({"id": color_id, "name": color_name, "swatchHex": swatch_hex})
        if color is None:
            raise ValueError("Invalid colour id (use lowercase letters, digits, dashes)")
        showroom["colors"].append(color)
    else:
        if color_name:
            color["name"] = _text(color_name, 60)
        if _HEX.fullmatch(swatch_hex or ""):
            color["swatchHex"] = swatch_hex.upper()
    clean = sanitize_asset(asset)
    if clean is None:
        raise ValueError("Uploaded asset has no usable URL")
    angles = [a for a in color["angles"] if a.get("checksum") != clean.get("checksum")]
    if len(angles) >= MAX_ANGLES:
        raise ValueError(f"At most {MAX_ANGLES} angles per colour")
    index = len(angles) if angle_index is None else max(0, min(len(angles), angle_index))
    angles.insert(index, clean)
    color["angles"] = angles
    if not showroom["defaultColorId"]:
        showroom["defaultColorId"] = color["id"]
    media["showroom"] = sanitize_showroom(showroom)
    return refresh_primary(media)


def update_showroom(media: dict[str, Any], payload: dict[str, Any]) -> dict[str, Any]:
    """Rename/recolour, reorder or delete angles, delete colours, set default.

    Angles are identified by checksum, so a reorder can only reference images
    that already belong to that colour (never inject new URLs).
    """
    media = dict(media or {})
    showroom = sanitize_showroom(media.get("showroom"))
    if showroom is None:
        raise ValueError("No showroom images yet")
    wanted = payload.get("colors")
    if not isinstance(wanted, list):
        raise ValueError("colors must be a list")
    by_id = {c["id"]: c for c in showroom["colors"]}
    colors: list[dict[str, Any]] = []
    for item in wanted:
        if not isinstance(item, dict):
            continue
        current = by_id.get(_text(item.get("id"), 40).lower())
        if current is None:
            continue
        by_checksum = {a.get("checksum"): a for a in current["angles"]}
        order = item.get("angleChecksums")
        angles = (
            [by_checksum[c] for c in order if c in by_checksum]
            if isinstance(order, list)
            else current["angles"]
        )
        swatch = _text(item.get("swatchHex"), 7)
        colors.append({
            "id": current["id"],
            "name": _text(item.get("name"), 60) or current["name"],
            "swatchHex": swatch.upper() if _HEX.fullmatch(swatch) else current["swatchHex"],
            "angles": angles,
        })
    colors = [c for c in colors if c["angles"]]
    if not colors:
        media.pop("showroom", None)
        return refresh_primary(media)
    media["showroom"] = sanitize_showroom({
        "defaultColorId": payload.get("defaultColorId"),
        "colors": colors,
    })
    return refresh_primary(media)
