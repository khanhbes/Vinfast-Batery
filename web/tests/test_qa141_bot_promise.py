"""QA 141: "Mình sẽ mở màn hình Tổng quan" must really open it."""
from __future__ import annotations

from assistant import engine


def test_a_promised_screen_becomes_a_navigate_action():
    text = "Bạn xem % pin ở Tổng quan. Mình sẽ mở màn hình **Tổng quan** để bạn xem nhé!"
    assert engine.promised_navigation(text, []) == {"name": "navigate", "args": {"screen": "overview"}}
    assert engine.promised_navigation("Mình mở Sức khỏe pin cho bạn.", []) == {
        "name": "navigate", "args": {"screen": "battery_health"}}


def test_an_offer_the_user_has_not_answered_opens_nothing():
    """QA 150: the question opened Premium and closed the chat."""
    for text in (
        "Sạc đến 80% tốt hơn cho pin. Bạn có muốn mình mở trang Pinova Premium để xem chi tiết các gói không?",
        "Nếu bạn muốn mình mở Sức khỏe pin thì nói nhé.",
        "Bạn cần mình mở Lịch sử sạc không",
    ):
        assert engine.promised_navigation(text, []) is None, text
    # A question earlier in the reply does not cancel a later promise.
    text = "Bạn muốn xem gói nào? Mình mở Pinova Premium cho bạn."
    assert engine.promised_navigation(text, []) == {"name": "navigate", "args": {"screen": "premium"}}


def test_no_promise_or_an_existing_action_adds_nothing():
    assert engine.promised_navigation("Pin của bạn còn 58%.", []) is None
    assert engine.promised_navigation("Mình sẽ mở cửa sổ khác.", []) is None
    stop = [{"name": "stop_charging", "args": {}}]
    assert engine.promised_navigation("Mình sẽ mở Sạc pin.", stop) is None
