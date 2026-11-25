# CLAUDE.md — ShipIt

Guidance for Claude Code when working in this repository. Read this file first in every session.

## What this project is

ShipIt is a **learning and portfolio project**. It's a small Python FastAPI service deployed to AWS ECS Fargate behind an Application Load Balancer. All infrastructure is in Terraform, and every change ships through GitHub Actions. Humans use only temporary credentials. CI holds only access keys that can do nothing except assume one scoped role each, because this account type blocks OIDC identity providers.

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
GitHub Actions ──assume-only key──▶ IAM roles (plan: read-only on PRs, apply: key lives in the approval-gated `production` environment)
Bootstrap (applied once, locally): S3 state bucket + CI roles + assume-only CI users
```

- **Region:** `eu-north-1`. This is the project's Region in AWS Settings and the only Region the AWS-managed project SCP allows (every other Region returns an explicit SCP deny; see `INTERVIEW.md`). Set it once in `infra/envs/dev/terraform.tfvars` and never hard-code it elsewhere. Free plan projects can't use multi-Region features. Before using a new service, check that it's on AWS's list of services the new experience supports.
- **VPC:** `10.0.0.0/16`, public subnets `10.0.1.0/24` and `10.0.2.0/24`. **No NAT Gateway, no private subnets** (ADR-001: cost).
- **Security groups:** `alb-sg` allows 80/443 from the internet. `app-sg` allows 8000 **only from `alb-sg`** (reference the security group, not a CIDR).
- **IAM:** task *execution* role (ECR pull, logs) is separate from task role (DynamoDB on this one table, `aps:RemoteWrite` on this one workspace).

## Repository layout

```
shipit/
├── app/                  # FastAPI service, tests, Dockerfile
├── observability/        # prometheus.yml, adot-config.yaml, grafana/ provisioning + dashboard JSON
├── infra/
│   ├── bootstrap/        # one-time: state bucket, CI roles, assume-only CI users (local state, applied from laptop)
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
| Scan image | `make scan` (`trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 shipit:local`; unfixed base-image CVEs aren't actionable) |
| Terraform fmt/validate/lint | `make tf-check` (`terraform fmt -check -recursive infra && tflint --recursive && trivy config infra`) |
| Plan dev | `make plan` (`cd infra/envs/dev && terraform plan -out=tfplan`) |
| All pre-commit hooks | `pre-commit run --all-files` |

AWS CLI login (AWS CLI ≥ 2.32): `aws login --profile dev`, then `export AWS_PROFILE=dev`. `aws sts get-caller-identity` shows `assumed-role/AccountFullAccessRole/...`. Never suggest `aws configure sso` or `aws configure` with access keys for Mori.

## Identity and access model

This account is on **AWS's new "projects" experience** (Builder ID login, AWS Settings), on the Free plan. AWS applies fixed guardrail SCPs that cannot be changed. In this account you **cannot** create IAM groups, console logins for IAM users, OIDC/SAML identity providers (`iam:*Provider*`), account aliases, or IAM Identity Center. Never suggest these, and never suggest "activate advanced features" (irreversible, removes the spend limit). Roles, policies, IAM users without console access, and access keys are allowed. Don't create roles under the `/managed/` path.

| Who | Identity | How credentials are obtained | Lifetime |
|---|---|---|---|
| Mori (laptop + console) | AWS Builder ID → `AccountFullAccessRole` (admin, managed by AWS) | Console login; `aws login --profile dev` for CLI/Terraform | Auto-refreshed, up to 12 h |
| CI, PR jobs | IAM user `github-ci-plan` (no console, one access key) → role `shipit-plan` | Key stored in GitHub environment `plan` → `configure-aws-credentials` with `role-to-assume` | ~1 h per job |
| CI, apply/deploy jobs | IAM user `github-ci-apply` (no console, one access key) → role `shipit-apply` | Key stored in GitHub environment `production` (requires Mori's approval) | ~1 h per job |
| App in ECS | Task role (app) + task execution role (ECS agent) | Provided by ECS | Rotated automatically |

- Each CI user's **only** permission is `sts:AssumeRole` on its one role. Each role's trust policy trusts only its own CI user ARN. All real permissions live on the roles.
- CI keys live only in GitHub **environment** secrets, never repository-level secrets, code or logs. Rotate every 90 days, and keep GitHub secret scanning enabled.
- Don't create IAM users or roles for Mori; his Builder ID session is already the admin.
- Why not OIDC: blocked by the project guardrail `iam:*Provider*`. This is documented in ADR-003. When explaining CI auth, note that OIDC is the standard elsewhere.
- Terraform state is read and written directly from CI. The **apply role** needs `s3:GetObject/PutObject/DeleteObject` on `dev/terraform.tfstate` and `dev/terraform.tfstate.tflock`, plus `s3:ListBucket` on the bucket. The **plan role** is read-only on resources and state, but still needs put/delete on the `.tflock` key, because `terraform plan` takes the lock.
- Later hardening: use IAM Access Analyzer policy generation (from CloudTrail activity) to replace broad permissions on `shipit-apply` with only what it actually used.

## Rules: safety and cost

These are hard rules. Follow them even if a task seems to need otherwise, and ask first.

1. **Never run `terraform apply`, `terraform destroy`, or any AWS CLI command that creates, changes or deletes resources without Mori's explicit confirmation in the chat.** `plan`, `validate`, `fmt` and read-only `aws ... describe/list/get` are fine.
2. **Never create a NAT Gateway, Elastic IP, EKS cluster, or anything with a fixed hourly cost** not already in the spec. If a fix seems to need one, stop and explain the cost first.
3. **Minimal long-lived credentials.** The only access keys allowed are one per assume-only CI user, stored only in GitHub environment secrets. Never create other access keys, never put keys in code, `.env` files, repository secrets or workflow files, and never print or echo credentials or tokens. Humans use `aws login`.
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

- `ci.yml` (PRs): ruff → pytest → docker build → trivy image scan (fail on fixable HIGH/CRITICAL, `--ignore-unfixed`).
- `deploy.yml` (push to `main`, app paths): job in `production` environment → `configure-aws-credentials` (apply user key + `role-to-assume`) → ECR login → build, tag `${{ github.sha }}`, push → render task definition → deploy with `wait-for-service-stability: true` → smoke test that `/version` returns the new SHA.
- `infra.yml` (infra paths): on PR, fmt/validate/tflint/trivy config, then `plan` with the **plan role** (job in the `plan` environment), posted as a PR comment. On merge, `apply` with the **apply role** (job in the `production` environment, which requires approval).
- Nightly drift check: `terraform plan -detailed-exitcode`; exit code 2 fails the job.
- `destroy.yml`: `workflow_dispatch` only, with a typed confirmation input.
- Set `permissions:` at minimum (`contents: read`; add `pull-requests: write` only where commenting). No `id-token: write`; OIDC isn't used.
- Credentials step: `aws-actions/configure-aws-credentials` with `aws-access-key-id` / `aws-secret-access-key` from **environment** secrets, plus `role-to-assume`, `role-session-name: gh-${{ github.run_id }}` and `role-duration-seconds: 3600`.
- **Pin third-party actions to a full commit SHA**, with the version in a comment.
- Use `concurrency:` groups so deploys and applies never overlap.
- Role ARNs and region go in workflow `env:` or repository **variables**, not secrets (they are not secret).

### Observability (`observability/`)

- Two layers: **CloudWatch** for ALB/ECS metrics and alarms → SNS email. **Prometheus (AMP) + Grafana** for app metrics.
- ADOT collector runs as a sidecar in the task, scrapes `localhost:8000/metrics` every 30s, and remote-writes to AMP with SigV4.
- Grafana data sources and dashboards are **provisioned from files**. Dashboard JSON is the source of truth; never only edit in the UI.
- Dashboard shows RED per route (rate, errors, p95 duration) plus `notes_created_total`. One alert: 5xx ratio > 5% for 5 min.

### Docs

- Every significant trade-off gets an ADR in `docs/adr/NNN-short-title.md`: Context, Decision, Consequences, Alternatives. Planned: 001 public subnets vs NAT, 002 ECS vs EKS, 003 assume-only CI keys (OIDC blocked by project guardrails), 004 S3 native locking, 005 CloudWatch + AMP.
- README holds the architecture diagram, local run steps, CI/CD explanation, cost section and screenshots.

## Git workflow

- Never commit directly to `main`. Branch names: `phase-N/short-desc`, `fix/...`, `docs/...`.
- Conventional commits: `feat(app): ...`, `feat(infra): ...`, `ci: ...`, `docs: ...`, `fix: ...`.
- Small PRs: one phase step per PR where possible. The PR description says what changed, why, and the plan summary for infra.
- Don't commit `tfplan`, `.terraform/`, `*.tfstate*`, `.env`, or anything with credentials. Keep `.gitignore` current.

## Build roadmap

Work **one phase at a time, in order**. At the start of a session, check this list. Then propose a short plan for the next unchecked step and wait for a go-ahead before writing lots of code. Tick items here when their "done when" is met.

- [ ] **Phase 0 — Setup:** AWS account on the new projects experience (Builder ID login, Free plan, project region noted, `aws login` profile `dev`), tools installed, repo with branch protection and pre-commit. *Done when:* `aws sts get-caller-identity --profile dev` works and a PR is blocked until checks pass.
- [ ] **Phase 1 — App:** FastAPI + tests + Dockerfile + compose with DynamoDB local, Prometheus, Grafana. *Done when:* `make up` serves `/health`, tests pass, Grafana on `localhost:3000` shows request rate and p95.
- [ ] **Phase 2 — Bootstrap:** state bucket; `shipit-plan` and `shipit-apply` roles with the S3 state permissions above (incl. the `.tflock` key for both); assume-only users `github-ci-plan` and `github-ci-apply`; keys stored in the GitHub `plan` and `production` environments (Mori creates the keys and pastes them into GitHub himself). *Done when:* `terraform init` in `envs/dev` uses the S3 backend and concurrent plans wait on the lock.
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