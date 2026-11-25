import json
import logging

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws
from prometheus_client import REGISTRY
from pydantic import ValidationError

from shipit_api.config import Settings, get_settings
from shipit_api.logging_config import JsonFormatter
from shipit_api.main import app
from shipit_api.repository import NotesRepository, get_repository

TABLE = "test-notes"


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        table = dynamodb.create_table(
            TableName=TABLE,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        app.dependency_overrides[get_repository] = lambda: NotesRepository(table)
        app.dependency_overrides[get_settings] = lambda: Settings(
            table_name=TABLE, aws_region="us-east-1", app_version="abc123"
        )
        yield TestClient(app)
        app.dependency_overrides.clear()


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_version(client):
    assert client.get("/version").json() == {"version": "abc123"}


def test_notes_crud(client):
    created = client.post("/notes", json={"title": "first", "body": "hello"})
    assert created.status_code == 201
    note = created.json()
    note_id = note["id"]
    assert note["title"] == "first"

    assert client.get(f"/notes/{note_id}").json() == note
    assert [n["id"] for n in client.get("/notes").json()] == [note_id]

    updated = client.patch(f"/notes/{note_id}", json={"body": "edited"})
    assert updated.status_code == 200
    assert updated.json()["body"] == "edited"
    assert updated.json()["title"] == "first"

    assert client.delete(f"/notes/{note_id}").status_code == 204
    assert client.get(f"/notes/{note_id}").status_code == 404
    assert client.get("/notes").json() == []


def test_missing_note_returns_404(client):
    assert client.get("/notes/nope").status_code == 404
    assert client.patch("/notes/nope", json={"title": "x"}).status_code == 404
    assert client.delete("/notes/nope").status_code == 404


def test_validation(client):
    assert client.post("/notes", json={"title": ""}).status_code == 422
    assert client.post("/notes", json={}).status_code == 422


def test_metrics_counts_notes_and_uses_route_templates(client):
    before = REGISTRY.get_sample_value("notes_created_total") or 0.0
    note_id = client.post("/notes", json={"title": "m"}).json()["id"]
    client.get(f"/notes/{note_id}")

    body = client.get("/metrics").text
    assert REGISTRY.get_sample_value("notes_created_total") == before + 1
    # Route template, not the raw path: one series per route, not per note.
    assert 'handler="/notes/{note_id}"' in body
    assert note_id not in body


def test_settings_read_from_env(monkeypatch):
    monkeypatch.setenv("TABLE_NAME", "t")
    monkeypatch.setenv("AWS_REGION", "eu-north-1")
    monkeypatch.setenv("APP_VERSION", "sha1")
    monkeypatch.setenv("DYNAMODB_ENDPOINT", "http://dynamodb:8000")
    s = Settings()
    assert (s.table_name, s.aws_region, s.app_version, s.dynamodb_endpoint) == (
        "t",
        "eu-north-1",
        "sha1",
        "http://dynamodb:8000",
    )


def test_settings_require_region_and_table(monkeypatch):
    for var in ("TABLE_NAME", "AWS_REGION"):
        monkeypatch.delenv(var, raising=False)
    with pytest.raises(ValidationError):
        Settings()


def test_json_log_format():
    record = logging.makeLogRecord(
        {"name": "shipit_api", "levelname": "INFO", "msg": "note created", "note_id": "n1"}
    )
    entry = json.loads(JsonFormatter().format(record))
    assert entry["message"] == "note created"
    assert entry["level"] == "INFO"
    assert entry["note_id"] == "n1"
