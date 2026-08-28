from __future__ import annotations

import os

import jwt


SHELLY_TRUST_PUBLIC_KEY = """-----BEGIN PUBLIC KEY-----
MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE3Kx+6C/0ZbnelYUgucUo4/X4xt1NCmEL
coyLpgkuLHume4VLZnQjtXeYgzr2FUdsO/ip8SzssSu3CEU9ArvB+yGIlW7l1yLt
wHVs/2zXrL0riL++7jdoQCpTGanFVzpM
-----END PUBLIC KEY-----"""


def verify_shelly_trust(token: str, payload: dict) -> bool:
    if not token:
        return False
    try:
        claims = jwt.decode(
            token,
            SHELLY_TRUST_PUBLIC_KEY,
            algorithms=["ES384"],
            options={"require": ["exp", "itg", "did"]},
        )
    except jwt.PyJWTError:
        return False
    expected_tag = os.environ.get("SHELLY_INTEGRATOR_TAG", "").strip()
    return bool(
        expected_tag
        and claims.get("itg") == expected_tag
        and str(claims.get("did")) == str(payload.get("deviceId"))
    )


def redact_secret(value: str) -> str:
    """Safe representation for diagnostic messages and tests."""
    return "<redacted>" if value else ""

