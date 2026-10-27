"""Lightweight tests exercised by CI before any deployment."""
from fastapi.testclient import TestClient

from app import app

client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_info():
    resp = client.get("/api/backend/info")
    assert resp.status_code == 200
    body = resp.json()
    assert body["service"] == "backend"
    assert "database" in body
