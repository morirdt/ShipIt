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
