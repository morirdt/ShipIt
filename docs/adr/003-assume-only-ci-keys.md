# ADR-003: Assume-only IAM users for CI instead of GitHub OIDC

- **Status:** Accepted
- **Date:** 2026-11-26
- **Phase:** 2 (bootstrap)

## Context

GitHub Actions needs AWS credentials to run `terraform plan` on pull requests and `terraform apply` / deploys on merge to `main`.

The standard answer is **GitHub OIDC**. GitHub signs a short-lived token for each job. An IAM OIDC identity provider in the account trusts GitHub, and a role's trust policy checks the token's claims (repo, branch, environment). No secret is stored anywhere, and credentials last about an hour.

This account can't do that. It runs on AWS's new "projects" experience (Free plan), and AWS-managed guardrail SCPs **deny `iam:*Provider*`**. No OIDC or SAML identity provider can be created, and an SCP deny can't be overridden by any IAM permission in the account. The guardrails also block IAM groups and console logins for IAM users. IAM users without console access, and their access keys, are allowed.

So CI needs *some* long-lived credential. The question is how to make one as weak as possible if it leaks.

## Decision

Use **one assume-only IAM user per CI privilege level**, and keep all real permissions on roles:

| CI job | IAM user (key holder) | Role assumed | Key stored in |
|---|---|---|---|
| PR plan | `github-ci-plan` | `shipit-plan` (read-only, state lock) | GitHub environment `plan` |
| Apply / deploy | `github-ci-apply` | `shipit-apply` | GitHub environment `production` (required reviewer, `main` only) |

- Each user's **only** permission is `sts:AssumeRole` + `sts:TagSession` on its own role.
- Each role's **trust policy** names exactly one user ARN. The plan key can't assume the apply role: the trust policy stops it, and the user's own policy doesn't allow it either.
- Jobs use `aws-actions/configure-aws-credentials` with the key plus `role-to-assume`. They get a ~1 h role session, and the session tags (repo, commit, actor) show up in CloudTrail.
- Keys are **not** created in Terraform, because the secret would sit in plaintext in the state. They're created with the AWS CLI and piped straight into `gh secret set`, so they never touch the screen, shell history or a file.
- Keys live only in GitHub **environment** secrets, never repository secrets. Role ARNs and the Region are repository **variables**, because they aren't secret.
- The users, roles and their permissions are managed in `infra/bootstrap/` and applied by a human. CI can't change its own permissions.

## Consequences

**Positive**
- A leaked key alone can do nothing except call `AssumeRole` on one role. That call is logged, and the resulting credentials expire within an hour.
- The apply key is only released to jobs from `main` after a human approves the `production` environment. The plan key only grants read access and the state lock.
- Pull requests from forks never receive environment secrets, so outsiders can't reach either key.
- The workflow code is identical to the OIDC version apart from the credentials step, so migrating later is small.

**Negative**
- Long-lived secrets exist and must be **rotated every 90 days** (two keys per user allow rotation without downtime). The next rotation is due 2027-02-24.
- Whoever can edit workflows on a branch that may use an environment can get at that environment's key. This is why `production` is restricted to `main`, which is protected by a ruleset, and why the plan role is read-only.
- More moving parts than OIDC: two users, key handling and a rotation process.
- GitHub secret scanning and push protection have to stay enabled as a backstop.

## Alternatives considered

| Option | Why not |
|---|---|
| **GitHub OIDC** | The standard approach and the best one elsewhere. Blocked here by the guardrail SCP (`iam:*Provider*`). |
| **Activate "advanced features"** to escape the guardrails | Irreversible, needs the Paid plan, and removes the spend limit, which is unacceptable for a learning account. |
| **One IAM user with permissions attached directly** (no roles) | A leaked key would give full, non-expiring access, and there'd be no separation between plan and apply. |
| **One user that can assume both roles** | The plan key, stored without an approval gate, could reach apply permissions. That defeats the `production` approval. |
| **Self-hosted runner with an instance role** | Removes stored keys, but needs an always-on EC2 instance (fixed hourly cost) and a runner to patch. |

## Revisit when

- The account leaves the projects experience, or the guardrail allows identity providers. Then switch to OIDC and delete both users.
- More environments are added (staging): one user and role pair per environment.
