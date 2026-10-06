"""Typed request context populated only by the Firebase auth middleware.

The annotations do not authenticate a request or provide default identities.
Protected routes must still use require_auth/require_admin before reading them.
"""
from typing import cast

from flask import Request, request as flask_request


class AuthenticatedRequest(Request):
    _uid: str
    _email: str | None
    _role: str | None
    _auth_failure: str | None


# Flask keeps this as a context-local proxy, not a captured request instance.
request = cast(AuthenticatedRequest, flask_request)
