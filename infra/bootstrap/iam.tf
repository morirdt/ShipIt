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

# ci_apply

# trivy:ignore:AWS-0143 IAM groups are blocked by the project guardrail SCP; single-purpose, assume-only CI user
resource "aws_iam_user" "ci_apply" {
  name = "github-ci-apply"
  path = "/ci/"
}

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

