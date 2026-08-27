from session_store import SessionStore


def test_empty_store(tmp_path):
    store = SessionStore(tmp_path / "state" / "current_session.json")
    assert store.load() is None


def test_session_persistence(tmp_path):
    path = tmp_path / "state" / "current_session.json"
    SessionStore(path).save({"session_id": "abc", "mode": "monitor_only"})
    assert SessionStore(path).load() == {
        "session_id": "abc",
        "mode": "monitor_only",
    }
