# ShipIt task runner. `make help` lists targets.
# Python tools run through uv inside app/, so they use the locked versions.

.DEFAULT_GOAL := help
.PHONY: help up down lint fmt test build scan tf-check plan

APP_VERSION ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo local)
IMAGE       ?= shipit:local

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

up: ## Run app + DynamoDB Local + Prometheus + Grafana
	APP_VERSION=$(APP_VERSION) docker compose up --build

down: ## Stop the local stack
	docker compose down

lint: ## Lint + format-check Python
	cd app && uv run ruff check . && uv run ruff format --check .

fmt: ## Auto-fix lint and format Python
	cd app && uv run ruff check --fix . && uv run ruff format .

test: ## Unit tests (moto, no AWS needed)
	cd app && uv run pytest -q

build: ## Build the container image
	docker build --build-arg APP_VERSION=$(APP_VERSION) -t $(IMAGE) app

# --ignore-unfixed: fail only on CVEs that have a fix we could apply. Unfixed Debian
# base-image CVEs would otherwise fail every build with nothing actionable.
scan: ## Scan the image for fixable HIGH/CRITICAL vulnerabilities
	trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE)

tf-check: ## Terraform fmt/validate/lint + trivy config scan
	terraform fmt -check -recursive infra && tflint --recursive && trivy config infra

plan: ## Terraform plan for dev
	cd infra/envs/dev && terraform plan -out=tfplan
