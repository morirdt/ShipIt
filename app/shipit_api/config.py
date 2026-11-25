from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Runtime configuration, read from environment variables."""

    # Git commit SHA baked in at build/deploy time (e.g. by CI).
    git_sha: str = "unknown"
    # DynamoDB table holding notes; partition key "id" (string).
    notes_table_name: str = "shipit-notes"
    aws_region: str = "us-east-1"
    # Optional override, e.g. http://localhost:8000 for DynamoDB Local.
    dynamodb_endpoint_url: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
