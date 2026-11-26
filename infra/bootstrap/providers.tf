provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id] # refuses to run against any other account

  default_tags {
    tags = {
      Project   = "shipit"
      Env       = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}