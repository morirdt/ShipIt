data "aws_caller_identity" "current" {}
locals {
  account_id           = data.aws_caller_identity.current.account_id
  tfstate_bucket_name  = "shipit-tfstate-${local.account_id}"
  dev_state_arn        = "${aws_s3_bucket.tfstate.arn}/dev/terraform.tfstate"
  dev_lock_arn         = "${aws_s3_bucket.tfstate.arn}/dev/terraform.tfstate.tflock"
  ecr_repo_arn_pattern = "arn:aws:ecr:${var.region}:${local.account_id}:repository/shipit-*"
}
