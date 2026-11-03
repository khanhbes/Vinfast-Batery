"""QA 145 — paying for Pro/Ultra with MoMo (APK build).

Prepaid periods, Pro → Ultra credit, codes once per account, the IPN
signature, an order fulfilled once, refunds.
"""
from datetime import datetime, timedelta, timezone

import pytest
from flask import Flask

from billing import features
from billing.entitlements import BillingError, EntitlementService
from billing.momo import CREATE_FIELDS, IPN_FIELDS, MomoClient, raw_signature, sign
from billing.payments import PaymentService
from billing.promos import PromoService
from billing.routes import create_billing_blueprint


class Clock:
    def __init__(self):
        self.now = datetime(2026, 11, 3, 3, 0, tzinfo=timezone.utc)

    def __call__(self):
        return self.now

    def advance(self, **kwargs):
        self.now += timedelta(**kwargs)


class FakeResponse:
    def __init__(self, data):
        self.data = data

    def json(self):
        return self.data


class FakeMomoHttp:
    """Plays MoMo: records requests, answers create/query/refund."""

    def __init__(self):
        self.calls = []
        self.query_result = {"resultCode": 1000, "message": "Đang chờ"}
        self.amounts = {}

    def post(self, url, json=None, timeout=None):
        self.calls.append((url, json))
        if url.endswith("/create"):
            self.amounts[json["orderId"]] = json["amount"]
            return FakeResponse({"resultCode": 0, "payUrl": f"https://pay.test/{json['orderId']}",
                                 "deeplink": f"momo://app?order={json['orderId']}", "qrCodeUrl": "qr"})
        if url.endswith("/query"):
            return FakeResponse({"orderId": json["orderId"], "amount": self.amounts.get(json["orderId"]),
                                 "transId": 555, "payType": "qr", **self.query_result})
        if url.endswith("/refund"):
            return FakeResponse({"resultCode": 0, "transId": 777})
        raise AssertionError(url)


SECRET = "K951B6PE1waDMi640xX08PD3vg6EkVlz"
ACCESS = "F8BBA842ECF85"


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def http():
    return FakeMomoHttp()


@pytest.fixture
def momo(http):
    return MomoClient(partner_code="MOMO", access_key=ACCESS, secret_key=SECRET, session=http)


@pytest.fixture
def services(clock, momo):
    entitlements = EntitlementService(clock=clock, enforced=True)
    promos = PromoService(clock=clock)
    payments = PaymentService(entitlements=entitlements, promos=promos, momo=momo, clock=clock,
                              enabled=True, public_base_url="https://api.test")
    return entitlements, promos, payments


def ipn_body(order, result_code=0, amount=None, trans_id=4088878653):
    body = {"partnerCode": "MOMO", "orderId": order["orderId"], "requestId": order["orderId"],
            "amount": order["amount"] if amount is None else amount, "orderInfo": "Pinova",
            "orderType": "momo_wallet", "transId": trans_id, "resultCode": result_code,
            "message": "Thành công.", "payType": "qr", "responseTime": 1730600000000, "extraData": ""}
    body["signature"] = sign(SECRET, {**body, "accessKey": ACCESS}, IPN_FIELDS)
    return body


def pay(payments, order, **kwargs):
    assert payments.ipn(ipn_body(order, **kwargs)) is True
    return payments._get(order["orderId"])


# -- signatures -----------------------------------------------------------
def test_create_signature_uses_momo_field_order(http, momo):
    momo.create(order_id="PNV1", amount=29000, order_info="Pinova Pro 1 tháng",
                redirect_url="https://api.test/r", ipn_url="https://api.test/i")
    _url, body = http.calls[0]
    assert body["requestType"] == "captureWallet" and "accessKey" not in body
    raw = raw_signature({**body, "accessKey": ACCESS}, CREATE_FIELDS)
    assert raw == ("accessKey=F8BBA842ECF85&amount=29000&extraData=&ipnUrl=https://api.test/i&orderId=PNV1"
                   "&orderInfo=Pinova Pro 1 tháng&partnerCode=MOMO&redirectUrl=https://api.test/r"
                   "&requestId=PNV1&requestType=captureWallet")
    assert body["signature"] == sign(SECRET, {**body, "accessKey": ACCESS}, CREATE_FIELDS)


def test_ipn_signature_is_checked(momo):
    body = ipn_body({"orderId": "PNV1", "amount": 29000})
    assert momo.verify_ipn(body) is True
    assert momo.verify_ipn({**body, "amount": 1000}) is False
    assert momo.verify_ipn({**body, "partnerCode": "OTHER"}) is False
    assert momo.verify_ipn({**body, "signature": ""}) is False


# -- pricing --------------------------------------------------------------
def test_new_purchase_and_extension_add_a_period(services, clock):
    entitlements, _promos, payments = services
    order = payments.checkout("u1", "pro", "month")
    assert order["amount"] == 29000 and order["status"] == "pending" and order["deeplink"]
    pay(payments, order)
    state = entitlements.state("u1", fresh=True)
    assert state["tier"] == "pro" and state["expiresAt"] == "2026-12-03T03:00:00Z"
    clock.advance(days=10)
    quote = payments.quote("u1", "pro", "month")
    assert quote["kind"] == "extend" and quote["amount"] == 29000
    assert quote["newExpiresAt"] == "2027-01-02T03:00:00Z"


def test_pro_to_ultra_turns_the_rest_of_pro_into_money_off(services, clock):
    _entitlements, _promos, payments = services
    pay(payments, payments.checkout("u1", "pro", "year"))  # 249.000đ for 365 days
    clock.advance(days=73)  # 292/365 left → 199.200đ → 199.000đ credit
    quote = payments.quote("u1", "ultra", "year")
    assert quote["kind"] == "upgrade" and quote["credit"] == 199000
    assert quote["amount"] == 449000 - 199000 and quote["days"] == 365
    assert quote["startsAt"] == "2027-01-15T03:00:00Z"


def test_credit_above_the_price_becomes_extra_ultra_days(services, clock):
    entitlements, _promos, payments = services
    pay(payments, payments.checkout("u1", "pro", "year"))
    quote = payments.quote("u1", "ultra", "month")  # credit 249.000đ > 49.000đ
    assert quote["credit"] == 249000 and quote["amount"] == 0 and quote["free"] is True
    assert quote["extraDays"] == int(200000 // (49000 / 30)) and quote["days"] == 30 + quote["extraDays"]
    order = payments.checkout("u1", "ultra", "month")
    assert order["status"] == "paid" and order["method"] == "free"
    state = entitlements.state("u1", fresh=True)
    assert state["tier"] == "ultra"
    # The carried value still counts as paid for the new span.
    assert entitlements.paid_state("u1")["paidAmount"] == 249000


def test_trial_or_admin_plans_carry_no_credit(services):
    entitlements, _promos, payments = services
    entitlements.start_trial("u1")  # Ultra trial
    assert payments.quote("u1", "pro", "month")["kind"] == "new"  # trial is not a paid plan
    entitlements.grant("u2", "pro", period="year")
    assert payments.quote("u2", "ultra", "year")["credit"] == 0


def test_moving_down_waits_for_the_plan_to_end(services):
    _entitlements, _promos, payments = services
    pay(payments, payments.checkout("u1", "ultra", "month"))
    with pytest.raises(BillingError) as error:
        payments.quote("u1", "pro", "month")
    assert error.value.code == "downgradeLater" and "03/12/2026" in error.value.message


def test_a_promo_applies_before_the_credit_and_is_used_once(services):
    entitlements, promos, payments = services
    promos.create({"code": "SALE20", "percentOff": 20, "validTo": "2027-01-01T00:00:00Z"})
    promos.redeem("u1", "SALE20")
    quote = payments.quote("u1", "pro", "year")
    assert quote["promoCode"] == "SALE20" and quote["amount"] == features.discounted(249000, 20)
    order = payments.checkout("u1", "pro", "year")
    pay(payments, order)
    assert promos.pending("u1") is None and promos.used_by("u1", "SALE20")
    assert promos.public(promos._get("SALE20"))["uses"] == 1
    with pytest.raises(BillingError) as error:
        promos.redeem("u1", "SALE20")
    assert error.value.code == "promoUsed"
    assert entitlements.paid_state("u1")["paidAmount"] == 199000


def test_a_code_with_a_total_runs_out(services):
    _entitlements, promos, payments = services
    promos.create({"code": "ONLY1", "percentOff": 100, "validTo": "2027-01-01T00:00:00Z", "maxUses": 1})
    promos.redeem("u1", "ONLY1")
    order = payments.checkout("u1", "ultra", "year")
    assert order["status"] == "paid" and order["amount"] == 0
    with pytest.raises(BillingError) as error:
        promos.redeem("u2", "ONLY1")
    assert error.value.code == "promoExhausted"


def test_a_code_that_ran_out_is_not_applied_at_checkout(services):
    _entitlements, promos, payments = services
    promos.create({"code": "TWOUSE", "percentOff": 50, "validTo": "2027-01-01T00:00:00Z", "maxUses": 1})
    promos.redeem("u1", "TWOUSE")
    promos.redeem("u2", "TWOUSE")  # both hold it before anyone paid
    pay(payments, payments.checkout("u1", "pro", "month"))
    assert payments.quote("u2", "pro", "month")["promoCode"] is None


# -- orders ---------------------------------------------------------------
def test_ipn_twice_and_query_grant_once(services, http, clock):
    entitlements, _promos, payments = services
    order = payments.checkout("u1", "pro", "month")
    pay(payments, order)
    pay(payments, order)
    http.query_result = {"resultCode": 0}
    clock.advance(seconds=30)
    assert payments.status("u1", order["orderId"])["status"] == "paid"
    assert entitlements.state("u1", fresh=True)["expiresAt"] == "2026-12-03T03:00:00Z"
    assert len(entitlements.history("u1")) == 1


def test_wrong_amount_is_kept_for_review(services):
    entitlements, _promos, payments = services
    order = payments.checkout("u1", "ultra", "year")
    saved = pay(payments, order, amount=1000)
    assert saved["status"] == "review" and entitlements.state("u1", fresh=True)["tier"] == "free"


def test_a_failed_payment_grants_nothing(services):
    entitlements, _promos, payments = services
    order = payments.checkout("u1", "pro", "month")
    assert pay(payments, order, result_code=1006)["status"] == "failed"
    assert entitlements.state("u1", fresh=True)["tier"] == "free"


def test_status_asks_momo_when_the_ipn_is_late(services, http, clock):
    entitlements, _promos, payments = services
    order = payments.checkout("u1", "pro", "month")
    assert payments.status("u1", order["orderId"])["status"] == "pending"  # < 10 s: no query
    assert not any(url.endswith("/query") for url, _ in http.calls)
    clock.advance(seconds=20)
    assert payments.status("u1", order["orderId"])["status"] == "pending"  # MoMo: waiting
    http.query_result = {"resultCode": 0}
    clock.advance(seconds=20)
    assert payments.status("u1", order["orderId"])["status"] == "paid"
    assert entitlements.state("u1", fresh=True)["tier"] == "pro"


def test_another_account_cannot_read_an_order(services):
    _entitlements, _promos, payments = services
    order = payments.checkout("u1", "pro", "month")
    with pytest.raises(BillingError) as error:
        payments.status("u2", order["orderId"])
    assert error.value.status == 404


def test_an_open_order_is_reused_and_orders_are_limited(services, clock):
    _entitlements, _promos, payments = services
    first = payments.checkout("u1", "pro", "month")
    assert payments.checkout("u1", "pro", "month")["orderId"] == first["orderId"]
    for _ in range(9):
        clock.advance(seconds=1)
        payments._orders = {k: {**v, "status": "failed"} for k, v in payments._orders.items()}
        payments.checkout("u1", "pro", "month")
    with pytest.raises(BillingError) as error:
        payments.checkout("u1", "pro", "year")
    assert error.value.code == "tooManyOrders"


def test_closed_payments_still_allow_a_free_code(clock, momo):
    entitlements = EntitlementService(clock=clock, enforced=True)
    promos = PromoService(clock=clock)
    payments = PaymentService(entitlements=entitlements, promos=promos, momo=momo, clock=clock,
                              enabled=False, public_base_url="https://api.test")
    with pytest.raises(BillingError) as error:
        payments.checkout("u1", "pro", "month")
    assert error.value.status == 503
    promos.create({"code": "FREE100", "percentOff": 100, "validTo": "2027-01-01T00:00:00Z"})
    promos.redeem("u1", "FREE100")
    assert payments.checkout("u1", "pro", "month")["status"] == "paid"


def test_refund_returns_the_money_and_ends_the_plan(services, http):
    entitlements, _promos, payments = services
    order = payments.checkout("u1", "pro", "month")
    pay(payments, order)
    refunded = payments.refund(order["orderId"], actor="admin")
    assert refunded["status"] == "refunded" and refunded["planRevoked"] is True
    assert entitlements.state("u1", fresh=True)["tier"] == "free"
    _url, body = http.calls[-1]
    assert body["transId"] == 4088878653 and body["amount"] == 29000
    with pytest.raises(BillingError):
        payments.refund(order["orderId"])


# -- HTTP -----------------------------------------------------------------
@pytest.fixture
def client(services):
    entitlements, promos, payments = services
    app = Flask(__name__)
    app.register_blueprint(create_billing_blueprint(
        entitlements=entitlements, promos=promos, payments=payments,
        auth_resolver=lambda: ("u1", "a@b.vn", "user"), require_admin=lambda f: f))
    return app.test_client()


def test_http_checkout_ipn_and_status(client, services):
    me = client.get("/api/billing/me").get_json()["data"]
    assert me["payments"]["momo"] is True
    quote = client.post("/api/billing/quote", json={"tier": "ultra", "period": "month"}).get_json()["data"]
    assert quote["amount"] == 49000
    order = client.post("/api/billing/checkout", json={"tier": "ultra", "period": "month"}).get_json()["data"]["order"]
    assert order["deeplink"].startswith("momo://")
    assert client.post("/api/billing/momo/ipn", json={**ipn_body(order), "signature": "x"}).status_code == 400
    assert client.post("/api/billing/momo/ipn", json=ipn_body(order)).status_code == 204
    data = client.get(f"/api/billing/orders/{order['orderId']}").get_json()["data"]
    assert data["order"]["status"] == "paid" and data["plan"]["tier"] == "ultra"
    items = client.get("/api/billing/orders").get_json()["data"]["items"]
    assert [i["orderId"] for i in items] == [order["orderId"]] and "uid" not in items[0]
    admin = client.get("/api/admin/billing/orders").get_json()["data"]
    assert admin["monthRevenue"] == 49000 and admin["items"][0]["transId"] == 4088878653


def test_return_page_sends_the_user_back_to_the_app(client):
    response = client.get("/thanh-toan/ket-qua?orderId=PNV1&resultCode=0")
    assert response.status_code == 200 and "package=com.bes.vinbatery" in response.get_data(as_text=True)
    assert "Đã thanh toán" in response.get_data(as_text=True)


def test_terms_page_is_public(client):
    response = client.get("/dieu-khoan-premium")
    assert response.status_code == 200 and "không tự gia hạn" in response.get_data(as_text=True)
