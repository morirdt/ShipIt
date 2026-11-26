terraform {
  required_version = ">= 1.10" # 1.10 is when S3 native locking (use_lockfile) arrived

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.74" # current is 6.74.0 → allows 6.74+, never 7.0
    }
  }
}
