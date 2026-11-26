output "tfstate_bucket_name" {
  description = "S3 bucket holding Terraform state. Used in every backend.tf."
  value       = aws_s3_bucket.tfstate.id
}

output "plan_role_arn" {
  description = "Role assumed by PR jobs (read-only plan). Goes into the GitHub repo variable for role-to-assume."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role assumed by merge/deploy jobs in the production environment. Goes into the GitHub repo variable for role-to-assume."
  value       = aws_iam_role.apply.arn
}

output "ci_plan_user_name" {
  description = "Assume-only IAM user whose access key lives in the GitHub 'plan' environment."
  value       = aws_iam_user.ci_plan.name
}

output "ci_apply_user_name" {
  description = "Assume-only IAM user whose access key lives in the GitHub 'production' environment."
  value       = aws_iam_user.ci_apply.name
}
