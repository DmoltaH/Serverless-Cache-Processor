data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = var.aws_region
  prefix     = var.project_name

  # IAM paths separate identities the deployer may manage (workload) from the
  # ones it must never touch (bootstrap). Prevents privilege escalation.
  bootstrap_iam_path = "/bootstrap/"
  workload_iam_path  = "/${var.project_name}/"

  # Deliberately does NOT start with the project prefix, so the deployer's
  # "${prefix}-*" S3 permissions never match the state bucket.
  state_bucket_name = "tfstate-${var.project_name}-${local.account_id}"
}

# Account-wide guardrail: no bucket in this account can ever be made public,
# regardless of bucket-level settings or policies.
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ElastiCache needs this service-linked role to manage ENIs in the VPC.
# Created here so the deployer role does not need iam:CreateServiceLinkedRole.
resource "aws_iam_service_linked_role" "elasticache" {
  count            = var.create_elasticache_service_linked_role ? 1 : 0
  aws_service_name = "elasticache.amazonaws.com"
}
