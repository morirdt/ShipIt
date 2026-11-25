# CLAUDE.md — ShipIt

Guidance for Claude Code when working in this repository. Read this file first in every session.

## What this project is

ShipIt is a **learning and portfolio project**. It's a small Python FastAPI service deployed to AWS ECS Fargate behind an Application Load Balancer. All infrastructure is in Terraform, and every change ships through GitHub Actions. GitHub authenticates to AWS with OIDC, so no AWS keys are stored anywhere.

The owner (Mori) is a DevOps engineer with OpenShift, GitLab CI, Helm, Argo, Prometheus and Grafana experience. He is building this to learn **AWS, Terraform, AWS networking and GitHub Actions** well enough to explain every design decision in a job interview.

**That changes how you should help:**

- Explain the *why* behind every non-obvious choice in a sentence or two. Where it helps, compare it to the OpenShift/Kubernetes/GitLab equivalent.
- Prefer clear, idiomatic, hand-written code over clever abstractions or large community modules. Don't use `terraform-aws-modules/vpc` or similar unless asked; writing these pieces by hand is part of the learning.
- For the `network` Terraform module (Phase 3), **guide and review first**. Suggest the structure and resources, let Mori write it, then review. Write it yourself only if he asks.
- When something breaks, explain the root cause and suggest a short entry for `INTERVIEW.md` (symptom → root cause → fix).

## Architecture

```
Users ──HTTP:80──▶ ALB (2 public subnets, 2 AZs) ──▶ ECS Fargate service (1 task per AZ)
                                                       ├─ app container (FastAPI, :8000, /metrics)
                                                       └─ ADOT collector sidecar ──remote write──▶ Amazon Managed Prometheus
Tasks ──▶ ECR (images) · DynamoDB (notes table) · CloudWatch (logs, alarms)
Grafana (local, docker compose) ──SigV4──▶ AMP query endpoint
GitHub Actions ──OIDC──▶ IAM roles (plan: read-only on PRs, apply: gated by `production` environment)
Bootstrap (applied once, locally): S3 state bucket + GitHub OIDC provider + CI roles
```

- **Region:** `eu-north-1`, the only Region the AWS-managed project SCP allows (set once in `infra/envs/dev/terraform.tfvars`; don't hard-code it elsewhere).
- **VPC:** `10.0.0.0/16`, public subnets `10.0.1.0/24` and `10.0.2.0/24`. **No NAT Gateway, no private subnets** (ADR-001: cost).
- **Security groups:** `alb-sg` allows 80/443 from the internet. `app-sg` allows 8000 **only from `alb-sg`** (reference the security group, not a CIDR).
- **IAM:** task *execution* role (ECR pull, logs) is separate from task role (DynamoDB on this one table, `aps:RemoteWrite` on this one workspace).

## Repository layout

```
shipit/
├── app/                  # FastAPI service, tests, Dockerfile
├── observability/        # prometheus.yml, adot-config.yaml, grafana/ provisioning + dashboard JSON
├── infra/
│   ├── bootstrap/        # one-time: state bucket, OIDC provider, CI roles (local state, applied from laptop)
│   ├── modules/
│   │   ├── network/      # VPC, subnets, IGW, routes, security groups
│   │   └── service/      # ECR, ECS, ALB, DynamoDB, AMP, IAM, logs, alarms, dashboard
│   └── envs/dev/         # wires modules together; backend.tf, variables, tfvars
├── .github/workflows/    # ci.yml, deploy.yml, infra.yml, destroy.yml
├── docs/                 # architecture.md, runbook.md, adr/NNN-title.md
├── INTERVIEW.md          # running log of problems and fixes
└── Makefile, README.md, .pre-commit-config.yaml
```

## Commands

Prefer `make` targets; add one when a new repeatable command appears.

| Task | Command |
|---|---|
| Run app + DynamoDB local + Prometheus + Grafana | `make up` (`docker compose up --build`) |
| Stop local stack | `make down` |
| Lint + format Python | `make lint` (`ruff check app && ruff format --check app`) |
| Unit tests | `make test` (`pytest app/tests -q`) |
| Build image | `make build` (`docker build -t shipit:local app`) |
| Scan image | `make scan` (`trivy image --severity HIGH,CRITICAL --exit-code 1 shipit:local`) |
| Terraform fmt/validate/lint | `make tf-check` (`terraform fmt -check -recursive infra && tflint --recursive && trivy config infra`) |
| Plan dev | `make plan` (`cd infra/envs/dev && terraform plan -out=tfplan`) |
| All pre-commit hooks | `pre-commit run --all-files` |

AWS CLI uses the profile `dev` with short-lived credentials from a console sign-in: `aws login --profile dev`, then `export AWS_PROFILE=dev`. **No IAM user access keys**, not even on the laptop.

The account was created with AWS's **new sign-up experience** (a "project" account). AWS runs the Organization and its SCPs for you until "advanced features" are activated. Activation can't be undone, needs the Paid plan and removes the spend limit. Consequences (see `INTERVIEW.md`):
- The project is pinned to **one Region (`eu-north-1`)**. Every other Region is denied by an SCP.
- IAM Identity Center and AWS Organizations aren't available, so use `aws login`, not SSO.
- Before using a new service, check it's on AWS's list of services supported by the new experience.

## Rules: safety and cost

These are hard rules. Follow them even if a task seems to need otherwise, and ask first.

1. **Never run `terraform apply`, `terraform destroy`, or any AWS CLI command that creates, changes or deletes resources without Mori's explicit confirmation in the chat.** `plan`, `validate`, `fmt` and read-only `aws ... describe/list/get` are fine.
2. **Never create a NAT Gateway, Elastic IP, EKS cluster, or anything with a fixed hourly cost** not already in the spec. If a fix seems to need one, stop and explain the cost first.
3. **No long-lived credentials anywhere.** No AWS access keys in code, `.env` files, GitHub secrets or workflow files. CI uses OIDC only. Never print or echo credentials or tokens.
4. **Least privilege.** Every IAM policy names specific actions and specific resource ARNs. `*` on actions or resources needs a comment explaining why (e.g. `ecr:GetAuthorizationToken`).
5. **State bucket and bootstrap are protected.** Keep `prevent_destroy` on the state bucket. Don't change `infra/bootstrap/` without asking.
6. Remind Mori to destroy the dev stack at the end of a working session (`destroy.yml` or `terraform destroy`). The ALB and public IPv4 addresses bill hourly.

## Conventions

### Python app (`app/`)

- Python 3.12, FastAPI, `uvicorn`, `boto3`, `pydantic-settings` for config.
- **Config from env vars only** (12-factor): `TABLE_NAME`, `AWS_REGION`, `APP_VERSION`, optional `DYNAMODB_ENDPOINT` for local.
- Endpoints: `GET /health` (no dependencies, fast), `GET /version` (returns `APP_VERSION` = git SHA), `POST/GET /notes`, `GET /metrics`.
- Metrics via `prometheus-fastapi-instrumentator`, plus a custom `notes_created_total` counter. **No high-cardinality labels** (no IDs or raw paths as label values).
- Structured JSON logs to stdout. No print statements.
- Tests: `pytest` with `moto` for DynamoDB. Every endpoint has at least one test. Tests must not need network or AWS credentials.
- Dockerfile: multi-stage, slim base, runs as non-root, `EXPOSE 8000`, no secrets baked in.

### Terraform (`infra/`)

- Terraform `>= 1.10` (native S3 locking), AWS provider pinned with `~>` in `versions.tf`. Commit `.terraform.lock.hcl`.
- Backend: S3 with `use_lockfile = true` and `encrypt = true`. **Don't use DynamoDB for locking** (deprecated).
- One resource type's logic per file where sensible: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. Plus `iam.tf`, `alb.tf`, etc. in larger modules.
- Every variable has `description` and `type`; add `validation` blocks for CIDRs and names. Every output has `description`.
- Use `for_each` over `count` for anything keyed (subnets per AZ).
- Default tags through the provider's `default_tags`: `Project = "shipit"`, `Env`, `ManagedBy = "terraform"`.
- Naming: `shipit-<env>-<thing>` (e.g. `shipit-dev-alb`).
- CloudWatch log groups have retention (7 days). ECR has `scan_on_push`, immutable tags and a lifecycle policy (keep 10).
- ECS service: deployment circuit breaker with rollback enabled. Target group type `ip`, health check `/health`.
- To rename or move resources, use `moved` blocks, not destroy/recreate.
- After any Terraform change, run `make tf-check` and `make plan` and summarise the plan, especially any **destroy/replace** actions.

### GitHub Actions (`.github/workflows/`)

- `ci.yml` (PRs): ruff → pytest → docker build → trivy image scan (fail on HIGH/CRITICAL).
- `deploy.yml` (push to `main`, app paths): OIDC → ECR login → build, tag `${{ github.sha }}`, push → render task definition → deploy with `wait-for-service-stability: true` → smoke test that `/version` returns the new SHA.
- `infra.yml` (infra paths): on PR, fmt/validate/tflint/trivy config, then `plan` with the **plan role**, posted as a PR comment. On merge, `apply` with the **apply role** in the `production` environment (requires approval).
- Nightly drift check: `terraform plan -detailed-exitcode`; exit code 2 fails the job.
- `destroy.yml`: `workflow_dispatch` only, with a typed confirmation input.
- Set `permissions:` at minimum (`id-token: write`, `contents: read`, add `pull-requests: write` only where commenting).
- **Pin third-party actions to a full commit SHA**, with the version in a comment.
- Use `concurrency:` groups so deploys and applies never overlap.
- Role ARNs and region go in workflow `env:` or repository **variables**, not secrets (they are not secret).

### Observability (`observability/`)

- Two layers: **CloudWatch** for ALB/ECS metrics and alarms → SNS email. **Prometheus (AMP) + Grafana** for app metrics.
- ADOT collector runs as a sidecar in the task, scrapes `localhost:8000/metrics` every 30s, and remote-writes to AMP with SigV4.
- Grafana data sources and dashboards are **provisioned from files**. Dashboard JSON is the source of truth; never only edit in the UI.
- Dashboard shows RED per route (rate, errors, p95 duration) plus `notes_created_total`. One alert: 5xx ratio > 5% for 5 min.

### Docs

- Every significant trade-off gets an ADR in `docs/adr/NNN-short-title.md`: Context, Decision, Consequences, Alternatives. Planned: 001 public subnets vs NAT, 002 ECS vs EKS, 003 OIDC vs access keys, 004 S3 native locking, 005 CloudWatch + AMP.
- README holds the architecture diagram, local run steps, CI/CD explanation, cost section and screenshots.

## Git workflow

- Never commit directly to `main`. Branch names: `phase-N/short-desc`, `fix/...`, `docs/...`.
- Conventional commits: `feat(app): ...`, `feat(infra): ...`, `ci: ...`, `docs: ...`, `fix: ...`.
- Small PRs: one phase step per PR where possible. The PR description says what changed, why, and the plan summary for infra.
- Don't commit `tfplan`, `.terraform/`, `*.tfstate*`, `.env`, or anything with credentials. Keep `.gitignore` current.

## Build roadmap

Work **one phase at a time, in order**. At the start of a session, check this list. Then propose a short plan for the next unchecked step and wait for a go-ahead before writing lots of code. Tick items here when their "done when" is met.

- [ ] **Phase 0 — Setup:** AWS account (Free plan, root MFA, `aws login` profile `dev` with no access keys, budgets), tools installed, repo with branch protection and pre-commit. *Done when:* `aws sts get-caller-identity --profile dev` works and a PR is blocked until checks pass.
- [ ] **Phase 1 — App:** FastAPI + tests + Dockerfile + compose with DynamoDB local, Prometheus, Grafana. *Done when:* `make up` serves `/health`, tests pass, Grafana on `localhost:3000` shows request rate and p95.
- [ ] **Phase 2 — Bootstrap:** state bucket, GitHub OIDC provider, plan and apply roles with trust scoped to `repo:<owner>/shipit:...`. *Done when:* `terraform init` in `envs/dev` uses the S3 backend and concurrent plans wait on the lock.
- [ ] **Phase 3 — Network + ECR:** VPC, 2 public subnets, IGW, routes, SGs, ECR (Mori writes the network module). *Done when:* apply succeeds and every route and rule can be explained.
- [ ] **Phase 4 — Service:** DynamoDB, log group, IAM roles, ECS cluster/task/service, ALB, circuit breaker; first image pushed by hand. *Done when:* `curl http://<alb-dns>/health` returns 200 and notes survive a task restart.
- [ ] **Phase 5 — App CI/CD:** `ci.yml`, `deploy.yml`. *Done when:* a merged change is live in about 5 min with no manual steps.
- [ ] **Phase 6 — Infra CI/CD:** `infra.yml` with plan comments, gated apply, nightly drift, `destroy.yml`. *Done when:* the plan shows as a PR comment, apply waits for approval, drift is caught.
- [ ] **Phase 7 — Observability:** CloudWatch alarms + SNS, AMP workspace, ADOT sidecar, Grafana → AMP, dashboard as code, one Prometheus alert, failure drill. *Done when:* Grafana shows live ECS metrics via AMP, and there are screenshots of a rollback, an alarm email and the error spike.
- [ ] **Phase 8 — Polish:** README, ADRs, demo recording, `destroy.yml` run, nothing left billing.

Stretch goals (only after Phase 8): HTTPS + Route 53 + ACM, private subnets with VPC endpoints, staging env, autoscaling + k6, Secrets Manager, OPA/Conftest, Infracost, EKS + Helm + Argo CD.

## How to work with Mori

- Before a multi-file change, state the plan in a few bullets and the files you will touch.
- After a change, say how to verify it (the exact command or URL) and what "good" looks like.
- If the spec and reality conflict (deprecated arguments, changed AWS behaviour), say so, cite the current docs, and propose the fix rather than silently diverging.
- When a question comes up that an interviewer might ask, point it out briefly.