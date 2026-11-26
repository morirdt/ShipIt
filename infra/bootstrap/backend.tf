terraform {
  backend "s3" {
    bucket       = "shipit-tfstate-887423027293" # literal value; variables aren't allowed here
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
    encrypt      = true
  }
}
