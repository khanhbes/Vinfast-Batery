"""QA 135 — Pinova Bot: Premium, promo, support, target edit, night, health."""
import pytest

from assistant.engine import SCREENS, describe_action, validate_action
from billing.entitlements import EntitlementService
from tests.test_assistant import CONTEXT, engine


def test_new_screens_and_actions_are_validated():
    for screen in ("premium", "help", "night_charging", "battery_health"):
        assert screen in SCREENS
        assert validate_action("navigate", {"screen": screen}, CONTEXT) == {"screen": screen}
    assert validate_action("open_premium", {"feature": "night_charging"}, CONTEXT) == {"feature": "night_charging"}
    assert validate_action("open_premium", {"feature": "free_money"}, CONTEXT) == {}
    assert validate_action("start_trial", {}, CONTEXT) == {}
    assert validate_action("apply_promo_code", {"code": " tet-2027 "}, CONTEXT) == {"code": "TET2027"}
    assert validate_action("apply_promo_code", {"code": "x"}, CONTEXT) is None
    assert validate_action("update_charge_target", {"percent": 90}, CONTEXT) == {"percent": 90}
    assert validate_action("update_charge_target", {"percent": 150}, CONTEXT) is None
    assert validate_action("set_night_plan", {"wake_at": "6:30", "target_percent": 95}, CONTEXT) == \
        {"wake_at": "6:30"}
    assert validate_action("set_night_plan", {"wake_at": "06:30", "target_percent": 85}, CONTEXT) == \
        {"wake_at": "06:30", "target_percent": 85}


@pytest.mark.parametrize("args", [
    {"subject": "Lỗi", "message": "ngắn"},
    {"subject": "Ổ sạc", "message": "api key của tôi là abcdef..."},
])
def test_support_drafts_need_content_and_never_secrets(args):
    assert validate_action("contact_support", args, CONTEXT) is None


def test_support_draft_keeps_the_owners_words():
    out = validate_action("contact_support", {"category": "scan", "subject": "Quét sai",
                                              "message": "Đồng hồ 68% mà app đọc 8%."}, CONTEXT)
    assert out == {"category": "scan", "subject": "Quét sai", "message": "Đồng hồ 68% mà app đọc 8%."}
    assert "Gửi" in describe_action({"name": "contact_support", "args": out})


def test_subscription_tool_reads_the_plan():
    billing = EntitlementService(enforced=True)
    billing.grant("u1", "pro", period="month")
    eng, _ = engine([[{"functionCall": {"name": "get_subscription", "args": {}}}],
                     [{"text": "Bạn đang dùng **Pro**."}]], entitlements=billing)
    result = eng.chat("u1", "tôi đang dùng gói gì", [], CONTEXT)
    assert result["reply"] == "Bạn đang dùng **Pro**."
    response = eng.gemini.calls[1]["contents"][-1]["parts"][0]["functionResponse"]["response"]
    assert response["tier"] == "pro" and response["features"]["target_charging"] is True


def test_health_tool_is_pro_and_reads_the_vehicle():
    billing = EntitlementService(enforced=True)
    eng, _ = engine([[{"functionCall": {"name": "get_battery_health", "args": {}}}],
                     [{"text": "Gói Pro mới xem được."}]], entitlements=billing,
                    health_reader=lambda uid, vid: {"estimate": {"sohPct": 92}})
    eng.chat("u1", "pin tôi chai bao nhiêu", [], CONTEXT)
    response = eng.gemini.calls[1]["contents"][-1]["parts"][0]["functionResponse"]["response"]
    assert response["error"] == "premiumRequired" and response["requiredTier"] == "pro"
    billing.grant("u1", "pro", period="month")
    eng.gemini.script = [[{"functionCall": {"name": "get_battery_health", "args": {}}}], [{"text": "92%"}]]
    eng.chat("u1", "pin tôi chai bao nhiêu", [], CONTEXT)
    response = eng.gemini.calls[-1]["contents"][-1]["parts"][0]["functionResponse"]["response"]
    assert response == {"estimate": {"sohPct": 92}}


def test_night_action_and_tool():
    eng, _ = engine([[{"functionCall": {"name": "get_night_plan", "args": {}}}],
                     [{"text": "Mình mở Sạc đêm."},
                      {"functionCall": {"name": "set_night_plan", "args": {"wake_at": "06:00"}}}]],
                    night_reader=lambda uid, vid: None)
    result = eng.chat("u1", "tối nay sạc để 6 giờ sáng đầy", [], CONTEXT)
    assert result["actions"] == [{"name": "set_night_plan", "args": {"wake_at": "06:00"}}]
    first = eng.gemini.calls[1]["contents"][-1]["parts"][0]["functionResponse"]["response"]
    assert first == {"plan": None}
    assert "set_night_plan" in eng.gemini.calls[0]["tools"]
    assert "Gói Pinova Premium" in eng.gemini.calls[0]["system"] or "Free" in eng.gemini.calls[0]["system"]
