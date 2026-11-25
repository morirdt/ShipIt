from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Runtime configuration, read only from environment variables (12-factor).

    pydantic-settings matches env vars to field names case-insensitively,
    so `table_name` is read from TABLE_NAME, and so on.
    """

    # DynamoDB table holding notes; partition key "id" (string).
    table_name: str
    # No default on purpose: a silent fallback Region would point the app at the
    # wrong DynamoDB endpoint. ECS and compose always set it.
    aws_region: str
    # Git commit SHA, set at build/deploy time by CI.
    app_version: str = "unknown"
    # Only set locally, e.g. http://dynamodb:8000 for DynamoDB Local.
    dynamodb_endpoint: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
