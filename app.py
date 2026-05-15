import json
import hmac
import os
from datetime import datetime, timezone
from pathlib import Path

from flask import Flask, jsonify, request


app = Flask(__name__)

# Configuracion por variables de entorno.
API_KEY = os.getenv("API_KEY", "")
REQUIRE_API_KEY = os.getenv("REQUIRE_API_KEY", "true").lower() == "true"
MAX_PAYLOAD_BYTES = int(os.getenv("MAX_PAYLOAD_BYTES", "8192"))
DATA_DIR = Path(os.getenv("DATA_DIR", "data"))
DATA_FILE = DATA_DIR / "telemetry.jsonl"
app.config["MAX_CONTENT_LENGTH"] = MAX_PAYLOAD_BYTES


def _client_ip() -> str:
    forwarded_for = request.headers.get("X-Forwarded-For", "")
    if forwarded_for:
        return forwarded_for.split(",", 1)[0].strip()
    return request.remote_addr or "unknown"


@app.errorhandler(413)
def payload_too_large(_error):
    return jsonify({"error": "payload too large"}), 413


@app.get("/health")
def health_check():
    return jsonify({"status": "ok"}), 200


@app.post("/api/esp32/data")
def receive_esp32_data():
    if REQUIRE_API_KEY and not API_KEY:
        return jsonify({"error": "server misconfigured: API_KEY is required"}), 500

    if REQUIRE_API_KEY:
        provided_key = request.headers.get("X-API-Key")
        if not provided_key or not hmac.compare_digest(provided_key, API_KEY):
            return jsonify({"error": "unauthorized"}), 401

    if not request.is_json:
        return jsonify({"error": "content-type must be application/json"}), 400

    payload = request.get_json(silent=True)
    if payload is None:
        return jsonify({"error": "invalid json"}), 400
    if not isinstance(payload, dict):
        return jsonify({"error": "json payload must be an object"}), 400
    if "device_id" not in payload:
        return jsonify({"error": "device_id is required"}), 400

    # Adjunta metadata de recepcion para facilitar trazabilidad.
    record = {
        "received_at": datetime.now(timezone.utc).isoformat(),
        "ip": _client_ip(),
        "data": payload,
    }

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with DATA_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")

    return jsonify({"message": "data received", "saved": True}), 201


if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    debug = os.getenv("DEBUG", "false").lower() == "true"
    app.run(host=host, port=port, debug=debug)