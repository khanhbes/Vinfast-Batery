"""MoMo e-wallet payments, API v2 (QA 145).

Only the APK build pays through MoMo; store builds use the store's billing.
The secret key stays in the Azure secret ``MOMO_SECRET_KEY``. Every call is
signed with HMAC-SHA256 over ``key=value`` pairs in the order MoMo lists
them; the IPN MoMo sends back is checked the same way before anything is
granted.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import uuid

import requests

TEST_ENDPOINT = "https://test-payment.momo.vn"
TIMEOUT_SECONDS = 30

CREATE_FIELDS = ("accessKey", "amount", "extraData", "ipnUrl", "orderId", "orderInfo",
                 "partnerCode", "redirectUrl", "requestId", "requestType")
IPN_FIELDS = ("accessKey", "amount", "extraData", "message", "orderId", "orderInfo", "orderType",
              "partnerCode", "payType", "requestId", "responseTime", "resultCode", "transId")
QUERY_FIELDS = ("accessKey", "orderId", "partnerCode", "requestId")
REFUND_FIELDS = ("accessKey", "amount", "description", "orderId", "partnerCode", "requestId",
                 "transId")


class MomoError(RuntimeError):
    """MoMo could not be reached or refused the request."""

    def __init__(self, code: str, message: str = "", result_code=None):
        super().__init__(message or code)
        self.code = code
        self.result_code = result_code


def raw_signature(values: dict, fields) -> str:
    return "&".join(f"{name}={'' if values.get(name) is None else values.get(name)}" for name in fields)


def sign(secret_key: str, values: dict, fields) -> str:
    return hmac.new(secret_key.encode("utf-8"), raw_signature(values, fields).encode("utf-8"),
                    hashlib.sha256).hexdigest()


class MomoClient:
    def __init__(self, *, partner_code: str, access_key: str, secret_key: str,
                 endpoint: str = TEST_ENDPOINT, session=None):
        self.partner_code = partner_code
        self.access_key = access_key
        self.secret_key = secret_key
        self.endpoint = endpoint.rstrip("/")
        self.session = session or requests

    @classmethod
    def from_env(cls, env=None):
        env = os.environ if env is None else env
        partner = str(env.get("MOMO_PARTNER_CODE") or "").strip()
        access = str(env.get("MOMO_ACCESS_KEY") or "").strip()
        secret = str(env.get("MOMO_SECRET_KEY") or "").strip()
        if not (partner and access and secret):
            return None
        return cls(partner_code=partner, access_key=access, secret_key=secret,
                   endpoint=str(env.get("MOMO_ENDPOINT") or TEST_ENDPOINT).strip())

    @property
    def sandbox(self) -> bool:
        return self.endpoint.startswith(TEST_ENDPOINT)

    def _post(self, path: str, body: dict) -> dict:
        try:
            response = self.session.post(self.endpoint + path, json=body, timeout=TIMEOUT_SECONDS)
            data = response.json()
        except Exception:
            raise MomoError("momoUnavailable", "Chưa liên lạc được MoMo.") from None
        if not isinstance(data, dict):
            raise MomoError("momoUnavailable", "MoMo trả lời không hợp lệ.")
        return data

    def create(self, *, order_id: str, amount: int, order_info: str, redirect_url: str,
               ipn_url: str, expire_minutes: int = 15) -> dict:
        values = {
            "accessKey": self.access_key, "amount": int(amount), "extraData": "",
            "ipnUrl": ipn_url, "orderId": order_id, "orderInfo": order_info,
            "partnerCode": self.partner_code, "redirectUrl": redirect_url,
            "requestId": order_id, "requestType": "captureWallet",
        }
        body = {k: v for k, v in values.items() if k != "accessKey"}
        body.update({"lang": "vi", "orderExpireTime": int(expire_minutes), "autoCapture": True,
                     "signature": sign(self.secret_key, values, CREATE_FIELDS)})
        data = self._post("/v2/gateway/api/create", body)
        if int(data.get("resultCode", -1)) != 0 or not data.get("payUrl"):
            raise MomoError("momoRejected", str(data.get("message") or "MoMo từ chối tạo đơn."),
                            data.get("resultCode"))
        return {"payUrl": data.get("payUrl"), "deeplink": data.get("deeplink"),
                "qrCodeUrl": data.get("qrCodeUrl")}

    def verify_ipn(self, body: dict) -> bool:
        if not isinstance(body, dict) or str(body.get("partnerCode") or "") != self.partner_code:
            return False
        given = str(body.get("signature") or "")
        expected = sign(self.secret_key, {**body, "accessKey": self.access_key}, IPN_FIELDS)
        return bool(given) and hmac.compare_digest(given, expected)

    def query(self, order_id: str) -> dict:
        """The order as MoMo sees it now (``resultCode`` 0 = paid)."""
        values = {"accessKey": self.access_key, "orderId": order_id,
                  "partnerCode": self.partner_code, "requestId": uuid.uuid4().hex}
        body = {k: v for k, v in values.items() if k != "accessKey"}
        body.update({"lang": "vi", "signature": sign(self.secret_key, values, QUERY_FIELDS)})
        data = self._post("/v2/gateway/api/query", body)
        if str(data.get("orderId") or "") != order_id:
            raise MomoError("momoUnavailable", "MoMo trả lời không khớp đơn.")
        return data

    def refund(self, *, order_id: str, trans_id, amount: int, description: str) -> dict:
        refund_id = f"{order_id}R{uuid.uuid4().hex[:6].upper()}"
        values = {"accessKey": self.access_key, "amount": int(amount), "description": description,
                  "orderId": refund_id, "partnerCode": self.partner_code,
                  "requestId": refund_id, "transId": int(trans_id)}
        body = {k: v for k, v in values.items() if k != "accessKey"}
        body.update({"lang": "vi", "signature": sign(self.secret_key, values, REFUND_FIELDS)})
        data = self._post("/v2/gateway/api/refund", body)
        if int(data.get("resultCode", -1)) != 0:
            raise MomoError("momoRefundRejected", str(data.get("message") or "MoMo từ chối hoàn tiền."),
                            data.get("resultCode"))
        return {"refundId": refund_id, "transId": data.get("transId")}
