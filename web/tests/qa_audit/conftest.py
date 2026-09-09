import os
import sys
import pytest
import tempfile
import shutil

# Ensure web/ directory is on sys.path
web_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if web_dir not in sys.path:
    sys.path.insert(0, web_dir)

# Set isolation BEFORE test modules import server. Never discover real credentials.
os.environ['APP_ENV'] = 'testing'
os.environ['FLASK_ENV'] = 'testing'
os.environ['ADMIN_EMAILS'] = 'admin@vinfast.vn'
os.environ['CORS_ORIGINS'] = 'http://localhost:3000'
os.environ['ALLOW_DEV_ADMIN_KEY'] = 'false'

@pytest.fixture(autouse=True)
def isolated_dependencies(monkeypatch):
    import server
    monkeypatch.setattr(server, '_firestore_db', None)
    monkeypatch.setattr(server, '_firebase_available', False)
    monkeypatch.setattr(server, '_firebase_auth', None)
    monkeypatch.setattr(server, '_ai_request_json', lambda *a, **kw: ({'success': False, 'error': 'AI unavailable (fixture)'}, 502))

@pytest.fixture(scope="session")
def flask_app():
    # Set environment variables for testing
    os.environ["APP_ENV"] = "testing"
    os.environ["FLASK_ENV"] = "testing"
    os.environ["DEV_ADMIN_KEY"] = "test-secret-dev-admin-key-32-bytes"
    os.environ["AI_SERVER_INTERNAL_TOKEN"] = "test-internal-token-secret-12345"
    os.environ["ADMIN_EMAILS"] = "admin@vinfast.vn"
    
    import server
    server.app.config["TESTING"] = True
    return server.app

@pytest.fixture
def client(flask_app):
    return flask_app.test_client()

@pytest.fixture
def temp_models_dir():
    temp_dir = tempfile.mkdtemp(prefix="vf_test_models_")
    yield temp_dir
    shutil.rmtree(temp_dir, ignore_errors=True)
