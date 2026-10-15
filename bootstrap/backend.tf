# Rename to backend.tf AFTER the first apply, then run:
#   terraform output -raw bootstrap_backend_hcl > backend.hcl
#   terraform init -migrate-state -backend-config=backend.hcl
# The bucket has to exist before it can hold this stack's own state.
terraform {
  backend "s3" {}
}
