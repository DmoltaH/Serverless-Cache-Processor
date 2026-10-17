# Backend blocks cannot use variables, so values are literal.
# The bucket is created by bootstrap/ (output state_bucket_name).
terraform {
  backend "s3" {
    bucket       = "tfstate-sre-assessment-483175530572"
    key          = "infra/terraform.tfstate"
    region       = "us-east-2"
    profile      = "deployer-role"
    encrypt      = true
    use_lockfile = true
  }
}
