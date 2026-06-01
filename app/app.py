"""Platform Console — secure internal web app (Flask).

Each route maps to an architectural pattern from the reference submission:
Managed Identity -> Key Vault, and App Service -> SQL over private endpoints.
All backend access is resilient: failures surface on the Platform Health tab
rather than crashing the app.
"""
import datetime
import logging

from flask import Flask, jsonify, render_template, request

import db
import keyvault
from config import Config

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("platform-console")

app = Flask(__name__)


def _now():
    return datetime.datetime.now(datetime.timezone.utc)


# --- Page + health ---------------------------------------------------------


@app.route("/")
def index():
    return render_template(
        "index.html",
        environment=Config.ENVIRONMENT,
        app_version=Config.APP_VERSION,
        semantic_version=Config.SEMANTIC_VERSION,
        deployed_at=Config.DEPLOYED_AT,
    )


@app.route("/health")
def health():
    """Lightweight liveness probe used by the App Service health check."""
    return jsonify(
        {
            "status": "healthy",
            "version": Config.APP_VERSION,
            "semantic_version": Config.SEMANTIC_VERSION,
            "environment": Config.ENVIRONMENT,
            "deployed_at": Config.DEPLOYED_AT,
        }
    )


@app.route("/api/health")
def api_health():
    """Deep dependency status used by the Platform Health tab."""
    checks = {}

    checks["app_service"] = {"status": "green", "detail": "Serving requests"}

    try:
        db.healthcheck()
        checks["sql"] = {"status": "green", "detail": "Connected (SELECT 1)"}
    except Exception as exc:  # noqa: BLE001 - surface any failure to the UI
        checks["sql"] = {"status": "red", "detail": str(exc)}

    try:
        keyvault.get_secret(Config.APP_SECRET_NAME)
        checks["key_vault"] = {"status": "green", "detail": "Secret accessible"}
    except Exception as exc:  # noqa: BLE001
        checks["key_vault"] = {"status": "red", "detail": str(exc)}

    if Config.APPINSIGHTS_CONNECTION_STRING:
        checks["app_insights"] = {"status": "green", "detail": "Configured"}
    else:
        checks["app_insights"] = {"status": "yellow", "detail": "Not configured"}

    checks["app_version"] = {
        "status": "green",
        "detail": f"{Config.APP_VERSION} @ {Config.DEPLOYED_AT or 'n/a'}",
    }

    overall = "green"
    if any(c["status"] == "red" for c in checks.values()):
        overall = "red"
    elif any(c["status"] == "yellow" for c in checks.values()):
        overall = "yellow"

    return jsonify({"overall": overall, "checks": checks})


# --- Feature flags ---------------------------------------------------------


@app.route("/api/flags")
def api_flags():
    return jsonify(db.get_flags())


@app.route("/api/flags/<int:flag_id>", methods=["POST"])
def api_toggle_flag(flag_id):
    body = request.get_json(silent=True) or {}
    if "is_enabled" not in body:
        return jsonify({"error": "is_enabled is required"}), 400
    db.set_flag(flag_id, bool(body["is_enabled"]))
    return jsonify({"ok": True})


# --- Deployment history ----------------------------------------------------


@app.route("/api/deployments")
def api_deployments():
    return jsonify(db.get_deployments())


@app.route("/api/deployments", methods=["POST"])
def api_add_deployment():
    body = request.get_json(silent=True) or {}
    required = ["environment", "version"]
    missing = [k for k in required if not body.get(k)]
    if missing:
        return jsonify({"error": f"missing fields: {', '.join(missing)}"}), 400
    db.add_deployment(
        environment=body["environment"],
        version=body["version"],
        semantic_version=body.get("semantic_version"),
        deployed_by=body.get("deployed_by", "pipeline"),
        status=body.get("status", "success"),
    )
    return jsonify({"ok": True}), 201


# --- Secret expiry monitor -------------------------------------------------


@app.route("/api/secrets/expiry")
def api_secret_expiry():
    secrets = keyvault.list_secret_expiries()
    now = _now()
    enriched = []
    for s in secrets:
        status, days = "green", None
        if s["expires_on"]:
            expires = datetime.datetime.fromisoformat(s["expires_on"])
            days = (expires - now).days
            if days < 7:
                status = "red"
            elif days <= 30:
                status = "amber"
        else:
            status = "green"  # no expiry set
        enriched.append({**s, "status": status, "days_remaining": days})
    return jsonify(enriched)


# --- Release notes ---------------------------------------------------------


@app.route("/api/releases")
def api_releases():
    return jsonify(db.get_releases())


@app.route("/api/releases", methods=["POST"])
def api_add_release():
    body = request.get_json(silent=True) or {}
    required = ["version", "semantic_version", "content", "published_by"]
    missing = [k for k in required if not body.get(k)]
    if missing:
        return jsonify({"error": f"missing fields: {', '.join(missing)}"}), 400
    note_id = db.add_release(
        version=body["version"],
        semantic_version=body["semantic_version"],
        content=body["content"],
        published_by=body["published_by"],
        items=body.get("items", []),
    )
    return jsonify({"ok": True, "id": note_id}), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
