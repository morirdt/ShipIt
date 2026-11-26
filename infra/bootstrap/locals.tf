data "aws_caller_identity" "current" {}
locals {
  account_id          = data.aws_caller_identity.current.account_id
  tfstate_bucket_name = "shipit-tfstate-${local.account_id}"
}
