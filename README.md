# ShipIt

A small FastAPI service deployed to AWS ECS Fargate behind an ALB, with all infrastructure in Terraform and every change shipped through GitHub Actions.

> Work in progress. Architecture, CI/CD and cost sections will be added as the phases land.

## Run locally

Requires Docker and [uv](https://docs.astral.sh/uv/).

```sh
make up      # app + DynamoDB Local + Prometheus + Grafana
make test    # unit tests (moto, no AWS needed)
make lint    # ruff check + format check
make down
```

| URL | What |
|---|---|
| http://localhost:8000/docs | API (Swagger UI) |
| http://localhost:8000/metrics | Prometheus metrics |
| http://localhost:9090 | Prometheus |
| http://localhost:3000 | Grafana (anonymous viewer; dashboard "ShipIt API") |

## AWS access

Humans never hold long-lived AWS credentials. CI holds the minimum: one access key per CI user, and those users can do nothing except assume one scoped role.

- **Locally:** short-lived credentials from a console sign-in.
  ```sh
  aws login --profile dev
  export AWS_PROFILE=dev
  aws sts get-caller-identity   # assumed-role/AccountFullAccessRole/...
  ```
- **CI:** two IAM users with no console access, `github-ci-plan` and `github-ci-apply`. Each has one permission, `sts:AssumeRole` on its own role (`shipit-plan`, `shipit-apply`), and each role trusts only its own user. The keys live only in GitHub **environment** secrets (`plan` and `production`; `production` requires approval). Jobs exchange them for ~1 h role sessions with `aws-actions/configure-aws-credentials`.
- **Why not OIDC?** GitHub OIDC is the usual choice, but this account runs on AWS's new "projects" experience. Its guardrail SCPs deny `iam:*Provider*`, so no OIDC identity provider can be created. See ADR-003.
