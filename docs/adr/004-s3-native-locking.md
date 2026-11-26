# ADR-004: Terraform state in S3 with native locking (no DynamoDB), SSE-S3 encryption

- **Status:** Accepted
- **Date:** 2026-11-26
- **Phase:** 2 (bootstrap)

## Context

Terraform state is the record of every resource Terraform manages, including every attribute it knows. It has to be:

- **shared**: my laptop and CI must see the same state;
- **locked**: two concurrent applies would corrupt it;
- **recoverable**: a bad write or accidental change must be reversible;
- **private**: state can contain sensitive values in plaintext.

For years the standard AWS setup was an S3 bucket for the state plus a **DynamoDB table for locking**. Terraform 1.10 added **S3 native locking** (`use_lockfile = true`). Terraform writes a `<key>.tflock` object with a conditional write ("only if it doesn't exist yet"), so S3 itself enforces that only one run holds the lock. The DynamoDB locking arguments are now deprecated.

There's also a bootstrap problem: the bucket that stores the state has to exist before any configuration can use it as a backend.

## Decision

**Storage and locking**
- One S3 bucket, `shipit-tfstate-<account-id>`, with one key per root module: `bootstrap/terraform.tfstate` and `dev/terraform.tfstate`.
- Backend: `use_lockfile = true`, `encrypt = true`. **No DynamoDB table.** `required_version >= 1.10`.
- Bootstrap chicken-and-egg: first applied with local state, then moved into the bucket with `terraform init -migrate-state`, and verified by a `plan` showing no changes.

**Bucket hardening**
- Versioning enabled. Noncurrent versions expire after 90 days, and incomplete multipart uploads after 7 days.
- Public access block (all four settings), `BucketOwnerEnforced` (ACLs disabled), and a bucket policy denying any request without TLS.
- `prevent_destroy` on the bucket.

**Encryption: SSE-S3 (`AES256`), not a customer-managed KMS key**
- The state contains no secrets by design: no access keys or passwords are created in Terraform.
- Access is already limited by IAM: only my admin session and the two CI roles, and the CI roles only see `dev/` keys.
- The Trivy finding AWS-0132 (no customer-managed key) is suppressed in code with this reason.

**Access**
- Both CI roles: `s3:ListBucket` on the bucket, read on `dev/terraform.tfstate`, and Get/Put/Delete on `dev/terraform.tfstate.tflock`. **`plan` needs write access to the lock object** because it takes the lock too.
- Only `shipit-apply` can write the state file. No role has `DeleteObject` on it: Terraform overwrites state and never deletes it during plan or apply.
- `bootstrap/` state is human-only.

## Consequences

**Positive**
- One less resource to create, secure, pay for and grant IAM permissions on. Locking lives next to the state it protects.
- Concurrent runs wait or fail cleanly ("Error acquiring the state lock"). Demonstrated with two terminals in Phase 2.
- Any bad state write can be rolled back by restoring a previous object version.
- SSE-S3 has no cost and no key policy to manage, and there's no risk of losing access to the state by deleting or misconfiguring a key.

**Negative**
- Requires Terraform ≥ 1.10 everywhere (laptop and CI).
- A run that crashes can leave a stale `.tflock` behind. It's cleared with `terraform force-unlock <id>` after confirming no run is active.
- SSE-S3 gives no separate decrypt permission and no CloudTrail record of who decrypted the state. Anyone with `s3:GetObject` on a key can read it.
- Server access logging is off (Trivy AWS-0089 suppressed). CloudTrail management events cover the bucket configuration, but not object reads.

## Alternatives considered

| Option | Why not |
|---|---|
| **S3 + DynamoDB lock table** | The previous standard. Now deprecated, and it means an extra table plus extra IAM permissions for nothing native locking doesn't already provide. |
| **Customer-managed KMS key (SSE-KMS)** | ~$1/month plus rotation charges, plus a key policy that must allow both CI roles. Deleting or misconfiguring the key makes the state unreadable. Worth it once state holds secrets, or once compliance requires decrypt audit logs. |
| **HCP Terraform / Terraform Cloud remote state** | Works, but moves state and runs to a third party and adds another account and token to manage. The point of this project is to learn the AWS-native setup. |
| **Local state only** | No sharing with CI, no locking between machines, and one lost laptop loses the state. |
| **One bucket per environment** | Stronger isolation, but more to manage for a single `dev` environment. Per-key IAM gives enough separation for now. |

## Revisit when

- State starts containing secrets (for example database passwords): move to SSE-KMS, or keep the secrets out of Terraform with Secrets Manager.
- More environments or accounts are added: consider a bucket per account.
