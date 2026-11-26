# ---------- plan: PR jobs (read-only) ----------

# trivy:ignore:AWS-0143 IAM groups are blocked by the project guardrail SCP; single-purpose, assume-only CI user
resource "aws_iam_user" "ci_plan" {
  name = "github-ci-plan"
  path = "/ci/"
}

# WHO may assume the role -> trust policy on the role. Has a principal, no resources.
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.ci_plan.arn]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "shipit-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600 # matches role-duration-seconds in the workflows
}

# WHAT the user may do -> identity policy on the user. Has resources, no principal.
data "aws_iam_policy_document" "ci_plan_assume" {
  statement {
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = [aws_iam_role.plan.arn]
  }
}

resource "aws_iam_user_policy" "ci_plan_assume" {
  name   = "assume-shipit-plan"
  user   = aws_iam_user.ci_plan.name
  policy = data.aws_iam_policy_document.ci_plan_assume.json
}

# ---------- apply: merge/deploy jobs (approval-gated) ----------

# trivy:ignore:AWS-0143 IAM groups are blocked by the project guardrail SCP; single-purpose, assume-only CI user
resource "aws_iam_user" "ci_apply" {
  name = "github-ci-apply"
  path = "/ci/"
}

# WHO may assume the role -> trust policy on the role. Has a principal, no resources.
data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.ci_apply.arn]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "shipit-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600 # matches role-duration-seconds in the workflows
}

# WHAT the user may do -> identity policy on the user. Has resources, no principal.
data "aws_iam_policy_document" "ci_apply_assume" {
  statement {
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = [aws_iam_role.apply.arn]
  }
}

resource "aws_iam_user_policy" "ci_apply_assume" {
  name   = "assume-shipit-apply"
  user   = aws_iam_user.ci_apply.name
  policy = data.aws_iam_policy_document.ci_apply_assume.json
}

# ---------- Terraform state access for the CI roles ----------
#
# The roles above can be assumed, but can't do anything yet. These policies let them
# use the dev Terraform state: every plan/apply reads the state file, and takes a lock
# by creating a .tflock object next to it (S3 native locking, use_lockfile = true).
# Only dev/ keys are granted: bootstrap/ state stays human-only.
# Infrastructure permissions (EC2, ECR, ...) are added per phase, starting in Phase 3.

data "aws_iam_policy_document" "plan_state" {
  # Bucket-level action: its resource is the bucket ARN itself (no /key).
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  # plan only reads the state. No PutObject: a PR job must never write state.
  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = [local.dev_state_arn]
  }

  # plan still takes the lock, so it must create and delete the lock object.
  # GetObject lets Terraform read who holds the lock for the "state locked" message.
  statement {
    sid       = "ManageLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.dev_lock_arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state-read"
  role   = aws_iam_role.plan.name
  policy = data.aws_iam_policy_document.plan_state.json
}

data "aws_iam_policy_document" "apply_state" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  # apply writes the new state after every change.
  # No DeleteObject: Terraform overwrites the state file and never deletes it during
  # plan/apply (only `terraform workspace delete` would). Versioning keeps old copies.
  statement {
    sid       = "ReadWriteState"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = [local.dev_state_arn]
  }

  statement {
    sid       = "ManageLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.dev_lock_arn]
  }
}

resource "aws_iam_role_policy" "apply_state" {
  name   = "terraform-state-readwrite"
  role   = aws_iam_role.apply.name
  policy = data.aws_iam_policy_document.apply_state.json
}