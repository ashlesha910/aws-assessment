"""
Minimal production-style FastAPI backend.

Exposes:
  GET /health              - liveness/readiness probe (used by ALB/EB health checks)
  GET /api/backend/info    - returns environment + DB connectivity status

Secrets (DB credentials) are read from AWS Secrets Manager at runtime via the
DB_SECRET_ARN environment variable - never baked into the image or source.
"""
import json
import os

from fastapi import FastAPI

app = FastAPI(title="Assessment Backend", version="1.0.0")

ENVIRONMENT = os.getenv("ENVIRONMENT", "local")
DB_SECRET_ARN = os.getenv("DB_SECRET_ARN", "")


def _load_db_config() -> dict:
    """Resolve DB credentials from Secrets Manager (lazy, so local dev works)."""
    if not DB_SECRET_ARN:
        return {"configured": False}
    try:
        import boto3  # imported lazily to keep local/test runs dependency-light

        client = boto3.client("secretsmanager")
        secret = client.get_secret_value(SecretId=DB_SECRET_ARN)
        data = json.loads(secret["SecretString"])
        return {
            "configured": True,
            "host": data.get("host"),
            "port": data.get("port"),
            "database": data.get("dbname") or data.get("database"),
        }
    except Exception as exc:  # noqa: BLE001 - surface status, never the secret
        return {"configured": True, "error": type(exc).__name__}


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "environment": ENVIRONMENT}


@app.get("/api/backend/info")
def info() -> dict:
    return {
        "service": "backend",
        "environment": ENVIRONMENT,
        "database": _load_db_config(),
    }
