# syntax=docker/dockerfile:1

# ---- build stage: resolve dependencies into a venv with uv ----
FROM python:3.12.16-slim-trixie AS builder

COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv /bin/uv

# Compile .pyc at build time (faster cold start) and copy instead of hardlink
# (the cache mount is a different filesystem).
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app

# Dependencies first, in their own layer: code changes don't re-install them.
COPY pyproject.toml uv.lock .python-version ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

# ---- runtime stage: no uv, no build tools, non-root ----
FROM python:3.12.16-slim-trixie

# Pull Debian security fixes released since the base image was built, then add
# a fixed numeric UID so runAsNonRoot-style checks can verify it (as in OpenShift).
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY shipit_api ./shipit_api

# CI passes the git SHA; ECS can also override it in the task definition.
ARG APP_VERSION=unknown
ENV APP_VERSION=${APP_VERSION} \
    PATH="/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1

USER 10001
EXPOSE 8000

# Used by Docker / docker compose. ECS ignores it: on Fargate, health comes from the
# ALB target group check (and optionally a task-definition healthCheck).
# python instead of curl: the slim image has no curl, and adding it grows the attack surface.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]

# --no-server-header: don't advertise the server software.
# --proxy-headers: trust X-Forwarded-For from the ALB for client IPs in access logs.
CMD ["uvicorn", "shipit_api.main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips", "*", "--no-server-header"]
