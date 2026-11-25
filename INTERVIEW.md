# Interview log

Problems hit while building ShipIt: symptom → root cause → fix, plus what it taught me.

## 2026-11-25 — "Full access" role denied by an SCP I didn't write

- **Symptom:** `sso:ListInstances` and `ec2:DescribeVpcs` (in most Regions) returned `AccessDenied ... with an explicit deny in a service control policy`, even though I was signed in with `AccountFullAccessRole`. The Organizations console said "not available to your project".
- **Root cause:** I signed up through AWS's new sign-up experience. It puts each "project" in its own member account, inside an Organization that AWS manages, with AWS-managed SCPs. Those SCPs:
  - pin the project to a single Region (`eu-north-1` for me),
  - block services the new experience doesn't support (IAM Identity Center, Organizations, and others).

  An explicit deny in an SCP overrides any IAM allow, so no IAM change inside the account can fix it.
- **How I found it:** read-only probes (`DescribeVpcs`, `ListTables`, `ListClusters`) across all Regions. `eu-north-1` was the only Region allowed. The opt-in Regions failed with `AuthFailure` instead, because they aren't enabled.
- **Fix:** Moved the project Region to `eu-north-1`. Used `aws login` for short-lived local credentials instead of SSO, with no IAM user access keys. Kept the managed setup rather than activating "advanced features", which is irreversible and removes the spend limit.
- **Takeaway:** When an `AccessDenied` mentions an SCP, look at the Organization layer, not the role's policies. (OpenShift analogy: a cluster-wide admission policy that a namespace admin's RBAC can't override.)

## 2026-11-25 — Q: Why run Trivy as a digest-pinned container instead of the Marketplace action?

- **Context:** `ci.yml` scans the image with `docker run aquasec/trivy:0.76.2@sha256:...` instead of `uses: aquasecurity/trivy-action@<tag>`.
- **Answer:** Supply chain. An action runs inside the job with the repo's `GITHUB_TOKEN` and any secrets that step can reach. A tag like `@v1` or `@0.x` is a movable pointer: if the action's repo is compromised, the attacker can repoint the tag, and every workflow that uses it runs their code on its next run. (This has really happened, e.g. `tj-actions/changed-files` in 2025.)
  - An image pinned by **digest** is content-addressed. The bytes can't change without the digest changing, so a compromised registry tag doesn't affect me.
  - The same logic is why every third-party action in this repo is pinned to a **full commit SHA**, with the version in a comment.
  - The job also limits the blast radius: `permissions: contents: read`, `persist-credentials: false` on checkout, and no AWS credentials in the PR workflow.
- **Trade-off:** Pins don't update themselves. I need Dependabot/Renovate, or a manual bump, to pick up new Trivy versions and vulnerability-DB fixes. (The DB itself is downloaded fresh on every run, so new CVEs are still detected.)
- **Takeaway:** Tags are mutable, digests and SHAs aren't. Pin anything that runs with credentials. (GitLab CI analogy: pinning `include:` templates and job `image:` by digest rather than `:latest`.)
