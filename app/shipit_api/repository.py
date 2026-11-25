"""DynamoDB-backed storage for notes."""

import uuid
from datetime import UTC, datetime
from functools import lru_cache
from typing import Any

import boto3
from boto3.dynamodb.conditions import Attr
from botocore.config import Config

from shipit_api.config import get_settings
from shipit_api.models import Note, NoteCreate, NoteUpdate

_BOTO_CONFIG = Config(
    retries={"mode": "standard", "total_max_attempts": 3},
    connect_timeout=2,
    read_timeout=5,
)


class NoteNotFoundError(Exception):
    pass


class NotesRepository:
    def __init__(self, table: Any) -> None:
        self._table = table
        self._client = table.meta.client

    def create(self, data: NoteCreate) -> Note:
        now = datetime.now(UTC).isoformat()
        item = {
            "id": str(uuid.uuid4()),
            "title": data.title,
            "body": data.body,
            "created_at": now,
            "updated_at": now,
        }
        self._table.put_item(Item=item, ConditionExpression=Attr("id").not_exists())
        return Note.model_validate(item)

    def get(self, note_id: str) -> Note:
        item = self._table.get_item(Key={"id": note_id}).get("Item")
        if item is None:
            raise NoteNotFoundError(note_id)
        return Note.model_validate(item)

    def list(self) -> list[Note]:
        # Scan is fine for a small notes table; switch to a GSI/query if it grows.
        paginator = self._client.get_paginator("scan")
        notes = [
            Note.model_validate(item)
            for page in paginator.paginate(TableName=self._table.name)
            for item in page["Items"]
        ]
        return sorted(notes, key=lambda n: n.created_at)

    def update(self, note_id: str, data: NoteUpdate) -> Note:
        changes = data.model_dump(exclude_unset=True, exclude_none=True)
        changes["updated_at"] = datetime.now(UTC).isoformat()

        names = {f"#{k}": k for k in changes}
        values = {f":{k}": v for k, v in changes.items()}
        expression = "SET " + ", ".join(f"#{k} = :{k}" for k in changes)
        try:
            response = self._table.update_item(
                Key={"id": note_id},
                UpdateExpression=expression,
                ExpressionAttributeNames=names,
                ExpressionAttributeValues=values,
                ConditionExpression=Attr("id").exists(),
                ReturnValues="ALL_NEW",
            )
        except self._client.exceptions.ConditionalCheckFailedException as exc:
            raise NoteNotFoundError(note_id) from exc
        return Note.model_validate(response["Attributes"])

    def delete(self, note_id: str) -> None:
        try:
            self._table.delete_item(
                Key={"id": note_id},
                ConditionExpression=Attr("id").exists(),
            )
        except self._client.exceptions.ConditionalCheckFailedException as exc:
            raise NoteNotFoundError(note_id) from exc


@lru_cache
def get_repository() -> NotesRepository:
    settings = get_settings()
    dynamodb = boto3.resource(
        "dynamodb",
        region_name=settings.aws_region,
        endpoint_url=settings.dynamodb_endpoint,
        config=_BOTO_CONFIG,
    )
    return NotesRepository(dynamodb.Table(settings.table_name))
