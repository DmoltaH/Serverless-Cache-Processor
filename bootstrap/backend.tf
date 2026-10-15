# This stack creates its own state bucket, so the very first apply runs with
# local state (this file absent); the state is then migrated here with
# `terraform init -migrate-state`. Backend blocks cannot use variables.
terraform {
  backend "s3" {
    bucket       = "tfstate-sre-assessment-483175530572"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
