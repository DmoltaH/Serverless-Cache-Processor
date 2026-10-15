# Deployment identity chain:
#   IAM user (access key, no console)  --sts:AssumeRole-->  deployer role (least privilege, 1h creds)
#
# The user holds no permissions of its own: a leaked key is only useful to
# request short-lived credentials, and deleting the key revokes everything.

resource "aws_iam_user" "deployer" {
  name = var.deployer_user_name
  path = local.bootstrap_iam_path
}

# Inline user policy instead of an IAM group: the account's AWS-managed SCP
# (new AWS experience) denies iam:CreateGroup / PutGroupPolicy / AddUserToGroup.
data "aws_iam_policy_document" "deployer_user" {
  statement {
    sid       = "AssumeDeployerRoleOnly"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.deployer.arn]
  }
}

resource "aws_iam_user_policy" "deployer" {
  name   = "assume-terraform-deployer-role"
  user   = aws_iam_user.deployer.name
  policy = data.aws_iam_policy_document.deployer_user.json
}

data "aws_iam_policy_document" "deployer_trust" {
  statement {
    sid     = "TrustDeployerUserOnly"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.deployer.arn]
    }
  }
}

resource "aws_iam_role" "deployer" {
  name                 = "${local.prefix}-terraform-deployer"
  path                 = local.bootstrap_iam_path
  description          = "Least-privilege role used by Terraform to deploy the ${local.prefix} infra stack."
  assume_role_policy   = data.aws_iam_policy_document.deployer_trust.json
  max_session_duration = var.deployer_session_duration_seconds
}

resource "aws_iam_policy" "deployer_network" {
  name        = "${local.prefix}-deployer-network"
  path        = local.bootstrap_iam_path
  description = "VPC, subnets, gateways, endpoints and security groups."
  policy      = data.aws_iam_policy_document.deployer_network.json
}

resource "aws_iam_policy" "deployer_compute" {
  name        = "${local.prefix}-deployer-compute"
  path        = local.bootstrap_iam_path
  description = "Lambda, API Gateway, CloudWatch Logs and alarms."
  policy      = data.aws_iam_policy_document.deployer_compute.json
}

resource "aws_iam_policy" "deployer_data" {
  name        = "${local.prefix}-deployer-data"
  path        = local.bootstrap_iam_path
  description = "S3, ElastiCache, Secrets Manager, workload IAM roles and Terraform state access."
  policy      = data.aws_iam_policy_document.deployer_data.json
}

resource "aws_iam_role_policy_attachment" "deployer" {
  for_each = {
    network = aws_iam_policy.deployer_network.arn
    compute = aws_iam_policy.deployer_compute.arn
    data    = aws_iam_policy.deployer_data.arn
  }

  role       = aws_iam_role.deployer.name
  policy_arn = each.value
}

# Ceiling for every role the deployer creates (e.g. the Lambda execution role).
# Even if a workload role is given a broad inline policy, its effective
# permissions can never exceed this boundary.
resource "aws_iam_policy" "workload_boundary" {
  name        = "${local.prefix}-workload-boundary"
  path        = local.bootstrap_iam_path
  description = "Permissions boundary for all ${local.prefix} workload roles."
  policy      = data.aws_iam_policy_document.workload_boundary.json
}
