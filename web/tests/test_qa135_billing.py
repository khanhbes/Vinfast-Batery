"""QA 135 — Pinova Premium: plans, trial, admin grants, promo codes, gates."""
from datetime import datetime, timedelta, timezone

import pytest
from flask import Flask

from assistant.quota import DailyQuota
from billing import features
from billing.entitlements import BillingError, EntitlementService
from billing.promos import PromoService, generate_code, normalize_code
from billing.routes import create_billing_blueprint
from shelly.service import SmartChargeError, SmartChargeService


class Clock:
    def __init__(self):
        self.now = datetime(2026, 10, 25, 3, 0, tzinfo=timezone.utc)

    def __call__(self):
        return self.now

    def advance(self, **kwargs):
        self.now += timedelta(**kwargs)


@pytest.fixture
def clock():
    return Clock()


def test_feature_table_and_limits():
    assert features.allows("free", "target_charging") is False
    assert features.allows("pro", "target_charging") is True
    assert features.allows("pro", "night_charging") is False
    assert features.allows("ultra", "night_charging") is True
    assert features.allows("free", "unknown_core_feature") is True  # core is never gated
    assert features.limit("free", "assistant_daily") == 10
    assert features.limit("pro", "assistant_daily") == 30
    assert features.limit("ultra", "assistant_daily") == 100
    assert features.limit("free", "history_days") == 30 and features.limit("pro", "history_days") is None
    assert [features.limit(t, "max_vehicles") for t in features.TIERS] == [1, 2, 10]
    assert features.limit("bogus", "assistant_daily") == 10  # unknown tier = Free
    assert "lifetime" not in features.PRICES["pro"] and "lifetime" not in features.PRICES["ultra"]
    assert features.PRICES == {"pro": {"month": 29000, "year": 249000},
                               "ultra": {"month": 49000, "year": 449000}}


def test_discount_rounds_down_to_thousand_dong():
    assert features.discounted(249000, 20) == 199000
    assert features.discounted(29000, 50) == 14000
    assert features.discounted(29000, 90) == 2000
    assert features.discounted(1500, 90) == 1000


def test_new_account_is_free_and_trial_is_once(clock):
    service = EntitlementService(clock=clock, enforced=True)
    assert service.tier("u1") == "free"
    assert service.summary("u1")["trialAvailable"] is True
    summary = service.start_trial("u1")
    assert summary["tier"] == "ultra" and summary["status"] == "trial"
    assert summary["trialAvailable"] is False and summary["features"]["night_charging"] is True
    with pytest.raises(BillingError) as error:
        service.start_trial("u1")
    assert error.value.code == "alreadyPremium"
    clock.advance(days=7, seconds=1)
    assert service.state("u1", fresh=True)["tier"] == "free"
    assert service.state("u1", fresh=True)["status"] == "expired"
    with pytest.raises(BillingError) as error:
        service.start_trial("u1")
    assert error.value.code == "trialUsed"


def test_admin_grant_extends_same_plan_and_revoke(clock):
    service = EntitlementService(clock=clock, enforced=True)
    first = service.grant("u1", "pro", period="month", actor="admin")
    assert first["tier"] == "pro" and first["status"] == "active"
    clock.advance(days=10)
    extended = service.grant("u1", "pro", period="month", actor="admin")
    expires = datetime.fromisoformat(extended["expiresAt"].replace("Z", "+00:00"))
    assert expires == datetime(2026, 10, 25, 3, 0, tzinfo=timezone.utc) + timedelta(days=60)
    upgraded = service.grant("u1", "ultra", days=14, actor="admin")
    assert upgraded["tier"] == "ultra"
    assert datetime.fromisoformat(upgraded["expiresAt"].replace("Z", "+00:00")) == clock.now + timedelta(days=14)
    revoked = service.revoke("u1", actor="admin")
    assert revoked["tier"] == "free" and revoked["status"] == "revoked"
    actions = [entry["action"] for entry in service.history("u1")]
    assert actions == ["grant", "grant", "grant", "revoke"]
    for bad in ({"tier": "free", "period": "month"}, {"tier": "pro", "days": 0},
                {"tier": "pro", "days": 9999}, {"tier": "pro"}, {"tier": "pro", "period": "lifetime"}):
        with pytest.raises(BillingError):
            service.grant("u2", bad["tier"], period=bad.get("period"), days=bad.get("days"))


def test_cached_tier_is_refreshed_after_writes(clock):
    service = EntitlementService(clock=clock, enforced=True)
    assert service.tier("u1") == "free"
    service.grant("u1", "pro", period="year")
    assert service.tier("u1") == "pro"  # write drops the cache


def test_enforcement_switch_opens_gates_but_shows_real_plan(clock):
    service = EntitlementService(clock=clock, enforced=False)
    assert service.allows("u1", "night_charging") is True
    summary = service.summary("u1")
    assert summary["tier"] == "free" and summary["features"]["night_charging"] is True
    assert summary["enforced"] is False


def test_tier_counts(clock):
    service = EntitlementService(clock=clock, enforced=True)
    service.grant("a", "pro", period="month")
    service.grant("b", "ultra", period="year")
    service.start_trial("c")
    service.grant("d", "pro", days=1)
    clock.advance(days=2)
    assert service.tier_counts() == {"pro": 1, "ultra": 1, "trial": 1, "expired": 1}


# -- promo codes --------------------------------------------------------------

def promo(clock, **overrides):
    body = {"percentOff": 20, "validTo": (clock.now + timedelta(days=30)).isoformat(),
            "tiers": ["pro", "ultra"], "periods": ["year"]}
    body.update(overrides)
    return body


def test_promo_create_and_redeem_quotes_only_allowed_plans(clock):
    promos = PromoService(clock=clock)
    item = promos.create(promo(clock, code="pinova-20"), actor="admin")
    assert item["code"] == "PINOVA20" and item["state"] == "active"
    quote = promos.redeem("u1", " pinova 20 ")
    assert quote["percentOff"] == 20
    assert quote["prices"] == {"pro": {"year": {"base": 249000, "final": 199000}},
                               "ultra": {"year": {"base": 449000, "final": 359000}}}
    assert promos.pending("u1")["code"] == "PINOVA20"
    assert promos.list()[0]["checks"] == 1
    promos.clear_pending("u1")
    assert promos.pending("u1") is None


def test_promo_generated_code_and_validation(clock):
    promos = PromoService(clock=clock)
    item = promos.create(promo(clock), actor="admin")
    assert len(item["code"]) == 8 and normalize_code(item["code"]) == item["code"]
    assert not set(generate_code(40)) & set("01IO")
    for bad in (promo(clock, percentOff=0), promo(clock, percentOff=95), promo(clock, validTo=None),
                promo(clock, validTo=(clock.now - timedelta(days=1)).isoformat()),
                promo(clock, tiers=["free"]), promo(clock, periods=["lifetime"]),
                promo(clock, code="AB"), promo(clock, tiers="pro")):
        with pytest.raises(BillingError):
            promos.create(bad)
    promos.create(promo(clock, code="SAME1"))
    with pytest.raises(BillingError) as error:
        promos.create(promo(clock, code="same1"))
    assert error.value.code == "codeExists"


def test_promo_states_expired_scheduled_inactive(clock):
    promos = PromoService(clock=clock)
    promos.create(promo(clock, code="LATER1", validFrom=(clock.now + timedelta(days=2)).isoformat()))
    promos.create(promo(clock, code="SOON01", validTo=(clock.now + timedelta(hours=1)).isoformat()))
    promos.create(promo(clock, code="OFF001"))
    promos.update("OFF001", {"active": False})
    with pytest.raises(BillingError) as error:
        promos.redeem("u1", "LATER1")
    assert error.value.code == "promoNotStarted"
    with pytest.raises(BillingError) as error:
        promos.redeem("u1", "OFF001")
    assert error.value.code == "promoInvalid"
    promos.redeem("u1", "SOON01")
    clock.advance(hours=2)
    assert promos.pending("u1") is None  # a remembered code ends with the code
    with pytest.raises(BillingError) as error:
        promos.redeem("u1", "SOON01")
    assert error.value.code == "promoExpired"


def test_promo_guessing_is_rate_limited(clock):
    promos = PromoService(clock=clock)
    promos.create(promo(clock, code="REAL01"))
    for _ in range(10):
        with pytest.raises(BillingError):
            promos.redeem("u1", "WRONG1")
    with pytest.raises(BillingError) as error:
        promos.redeem("u1", "REAL01")
    assert error.value.code == "promoRateLimited"
    assert promos.redeem("u2", "REAL01")["code"] == "REAL01"  # per account
    clock.advance(minutes=11)
    assert promos.redeem("u1", "REAL01")["code"] == "REAL01"


# -- routes -------------------------------------------------------------------

def client(clock, uid="u1"):
    app = Flask(__name__)
    entitlements = EntitlementService(clock=clock, enforced=True)
    promos = PromoService(clock=clock)
    audits = []
    app.register_blueprint(create_billing_blueprint(
        entitlements=entitlements, promos=promos,
        auth_resolver=lambda: (uid, "u@x", "user") if uid else (None, None, None),
        require_admin=lambda f: f, audit=lambda *args: audits.append(args),
        user_lookup=lambda q: {"uid": "u1", "email": "u@x"} if q in ("u1", "u@x") else None))
    return app.test_client(), entitlements, promos, audits


def test_routes_me_trial_promo(clock):
    http, _, promos, _ = client(clock)
    me = http.get("/api/billing/me").get_json()["data"]
    assert me["tier"] == "free" and me["trialAvailable"] is True and me["pendingPromo"] is None
    assert me["features"]["target_charging"] is False and me["limits"]["assistant_daily"] == 10
    trial = http.post("/api/billing/trial").get_json()["data"]
    assert trial["tier"] == "ultra" and trial["status"] == "trial"
    again = http.post("/api/billing/trial")
    assert again.status_code == 409 and again.get_json()["code"] == "alreadyPremium"
    promos.create(promo(clock, code="HELLO1"))
    assert http.post("/api/billing/promo", json={"code": "hello1"}).get_json()["data"]["code"] == "HELLO1"
    assert http.get("/api/billing/me").get_json()["data"]["pendingPromo"]["percentOff"] == 20
    wrong = http.post("/api/billing/promo", json={"code": "NOPE11"})
    assert wrong.status_code == 404 and wrong.get_json()["userMessage"] == "Mã khuyến mãi không đúng."


def test_routes_need_login(clock):
    http, *_ = client(clock, uid=None)
    assert http.get("/api/billing/me").status_code == 401
    assert http.post("/api/billing/trial").status_code == 401


def test_admin_routes_grant_revoke_promos_with_audit(clock):
    http, _, _, audits = client(clock)
    found = http.get("/api/admin/billing/user?q=u@x").get_json()["data"]
    assert found["user"]["uid"] == "u1" and found["plan"]["tier"] == "free"
    assert http.get("/api/admin/billing/user?q=ghost").status_code == 404
    granted = http.post("/api/admin/billing/grant", json={"uid": "u1", "tier": "ultra", "period": "year"})
    assert granted.get_json()["data"]["tier"] == "ultra"
    assert http.get("/api/admin/billing/stats").get_json()["data"]["counts"]["ultra"] == 1
    assert http.post("/api/admin/billing/revoke", json={"uid": "u1"}).get_json()["data"]["tier"] == "free"
    created = http.post("/api/admin/promos", json=promo(clock, code="TET2027", percentOff=30))
    assert created.get_json()["data"]["code"] == "TET2027"
    patched = http.patch("/api/admin/promos/tet2027", json={"active": False})
    assert patched.get_json()["data"]["state"] == "inactive"
    assert [item["code"] for item in http.get("/api/admin/promos").get_json()["data"]["items"]] == ["TET2027"]
    assert [a[0] for a in audits] == ["billing_grant", "billing_revoke", "promo_create", "promo_update"]
    bad = http.post("/api/admin/promos", json=promo(clock, percentOff=100))
    assert bad.status_code == 400 and bad.get_json()["code"] == "invalidPromo"


# -- gates ----------------------------------------------------------------------

def test_assistant_quota_follows_the_plan(clock):
    plans = {"free": "free", "pro": "pro"}
    quota = DailyQuota(limit_for=lambda uid: features.limit(plans[uid], "assistant_daily"))
    assert quota.limit_for("free") == 10 and quota.limit_for("pro") == 30
    for _ in range(10):
        assert quota.take("free")[0] is True
    assert quota.take("free") == (False, 0)
    assert quota.take("pro") == (True, 29)
    broken = DailyQuota(limit=7, limit_for=lambda uid: 1 / 0)
    assert broken.limit_for("x") == 7  # a billing hiccup falls back, never blocks


def test_smart_charge_gate_raises_premium_required(clock):
    service = SmartChargeService(None, None, None, clock=clock)
    service.require_feature("u1", "target_charging")  # no billing wired = allowed
    service.entitlements = EntitlementService(clock=clock, enforced=True)
    with pytest.raises(SmartChargeError) as error:
        service.require_feature("u1", "target_charging")
    assert error.value.code == "premiumRequired" and error.value.status == 403 and "Pro" in error.value.message
    with pytest.raises(SmartChargeError) as error:
        service.require_feature("u1", "learning_train")
    assert "Ultra" in error.value.message
    service.entitlements.grant("u1", "pro", period="month")
    service.require_feature("u1", "target_charging")
