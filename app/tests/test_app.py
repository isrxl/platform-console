import datetime

import pyodbc
import pytest

import app as app_module
import db
import keyvault
from config import short_sha


@pytest.fixture
def client():
    app_module.app.config["TESTING"] = True
    return app_module.app.test_client()


def test_health_returns_version(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["status"] == "healthy"
    assert "version" in body
    assert "environment" in body


def test_short_sha_truncates_git_hash():
    full = "5372a0c8e3fe6026dacdc3406ac8bf48b118aa38"
    assert short_sha(full) == "5372a0c"
    assert short_sha("dev-local") == "dev-local"


def test_api_health_all_green(client, monkeypatch):
    monkeypatch.setattr(db, "healthcheck", lambda: True)
    monkeypatch.setattr(keyvault, "get_secret", lambda name: "secret")
    monkeypatch.setattr(app_module.Config, "APPINSIGHTS_CONNECTION_STRING", "x")
    body = client.get("/api/health").get_json()
    assert body["overall"] == "green"
    assert body["checks"]["sql"]["status"] == "green"
    assert body["checks"]["key_vault"]["status"] == "green"


def test_api_health_reports_sql_failure(client, monkeypatch):
    def boom():
        raise RuntimeError("no connection")

    monkeypatch.setattr(db, "healthcheck", boom)
    monkeypatch.setattr(keyvault, "get_secret", lambda name: "secret")
    body = client.get("/api/health").get_json()
    assert body["overall"] == "red"
    assert body["checks"]["sql"]["status"] == "red"


def test_flags_listing(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "get_flags",
        lambda: [{"id": 1, "flag_name": "dark_mode", "environment": "test", "is_enabled": False, "updated_at": None, "updated_by": "system"}],
    )
    body = client.get("/api/flags").get_json()
    assert body[0]["flag_name"] == "dark_mode"


def test_toggle_flag_requires_is_enabled(client):
    resp = client.post("/api/flags/1", json={})
    assert resp.status_code == 400


def test_toggle_flag_ok(client, monkeypatch):
    captured = {}
    monkeypatch.setattr(db, "set_flag", lambda fid, enabled: captured.update(fid=fid, enabled=enabled))
    resp = client.post("/api/flags/5", json={"is_enabled": True})
    assert resp.status_code == 200
    assert captured == {"fid": 5, "enabled": True}


def test_add_deployment_validation(client):
    resp = client.post("/api/deployments", json={"environment": "prod"})
    assert resp.status_code == 400


def test_add_deployment_ok(client, monkeypatch):
    monkeypatch.setattr(db, "add_deployment", lambda **kw: None)
    resp = client.post(
        "/api/deployments",
        json={"environment": "prod", "version": "abc123", "semantic_version": "v1.0.0"},
    )
    assert resp.status_code == 201


def test_get_connection_schema_init_no_recursion(monkeypatch):
    """Regression: init_schema must not call get_connection (infinite recursion)."""
    db._schema_initialized = False

    class FakeConn:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def cursor(self):
            return self

        def execute(self, *args, **kwargs):
            return self

        def fetchone(self):
            return (1,)

        def commit(self):
            pass

    monkeypatch.setattr(db, "_connection_string", lambda: "fake-cs")
    monkeypatch.setattr(pyodbc, "connect", lambda *args, **kwargs: FakeConn())
    db.get_connection()


def test_secret_expiry_status_bands(client, monkeypatch):
    now = datetime.datetime.now(datetime.timezone.utc)
    monkeypatch.setattr(
        keyvault,
        "list_secret_expiries",
        lambda: [
            {"name": "fresh", "expires_on": (now + datetime.timedelta(days=90)).isoformat()},
            {"name": "soon", "expires_on": (now + datetime.timedelta(days=10)).isoformat()},
            {"name": "expiring", "expires_on": (now + datetime.timedelta(days=2)).isoformat()},
            {"name": "noexpiry", "expires_on": None},
        ],
    )
    rows = {r["name"]: r for r in client.get("/api/secrets/expiry").get_json()}
    assert rows["fresh"]["status"] == "green"
    assert rows["soon"]["status"] == "amber"
    assert rows["expiring"]["status"] == "red"
    assert rows["noexpiry"]["status"] == "green"


def test_add_release_validation(client):
    resp = client.post("/api/releases", json={"version": "abc"})
    assert resp.status_code == 400


def test_add_release_ok(client, monkeypatch):
    monkeypatch.setattr(db, "add_release", lambda **kw: 42)
    resp = client.post(
        "/api/releases",
        json={
            "version": "abc123",
            "semantic_version": "v1.2.0",
            "content": "Notes",
            "published_by": "tester",
            "items": [{"item_type": "feature", "description": "new tab"}],
        },
    )
    assert resp.status_code == 201
    assert resp.get_json()["id"] == 42
