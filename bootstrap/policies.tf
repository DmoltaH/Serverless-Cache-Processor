# Least-privilege permissions for the deployer role.
#
# Scoping strategy, from strongest to weakest, depending on what each AWS
# service supports:
#   1. Resource ARN by name prefix "${prefix}-*"  (Lambda, S3, ElastiCache, Logs, Secrets, IAM)
#   2. Resource ARN by account + region             (EC2/VPC, API Gateway: IDs are random)
#   3. Global deny outside the allowed region       (all regional services)
# Read-only Describe/List calls that AWS does not support at resource level use "*".

locals {
  ec2_arn_scope     = "arn:${local.partition}:ec2:${local.region}:${local.account_id}:*"
  lambda_fn_arn     = "arn:${local.partition}:lambda:${local.region}:${local.account_id}:function:${local.prefix}-*"
  workload_role_arn = "arn:${local.partition}:iam::${local.account_id}:role${local.workload_iam_path}*"
  bucket_arn        = "arn:${local.partition}:s3:::${local.prefix}-*"
  secret_arn        = "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${local.prefix}/*"
  elasticache_arn   = "arn:${local.partition}:elasticache:${local.region}:${local.account_id}:*:${local.prefix}-*"
  log_group_arns = [
    "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.prefix}-*",
    "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/apigateway/${local.prefix}-*",
  ]
}

# ---------------------------------------------------------------------------
# Network: VPC, subnets, IGW, NAT, route tables, S3 gateway endpoint, SGs
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deployer_network" {
  statement {
    sid         = "DenyOutsideAllowedRegion"
    effect      = "Deny"
    not_actions = ["iam:*", "sts:*"]
    resources   = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid       = "Ec2ReadOnly"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  statement {
    sid = "ManageNetwork"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:DisassociateAddress",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateVpcEndpoint",
      "ec2:ModifyVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = [local.ec2_arn_scope]
  }
}

# ---------------------------------------------------------------------------
# Compute & edge: Lambda, API Gateway (HTTP API), CloudWatch Logs & alarms
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deployer_compute" {
  statement {
    sid = "ManageProjectLambdas"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:PublishVersion",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:PutFunctionConcurrency",
      "lambda:DeleteFunctionConcurrency",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:Get*",
      "lambda:List*",
    ]
    resources = [local.lambda_fn_arn]
  }

  statement {
    sid       = "PassWorkloadRolesToLambdaOnly"
    actions   = ["iam:PassRole"]
    resources = [local.workload_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid     = "ManageHttpApis"
    actions = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"]
    resources = [
      "arn:${local.partition}:apigateway:${local.region}::/apis",
      "arn:${local.partition}:apigateway:${local.region}::/apis/*",
      "arn:${local.partition}:apigateway:${local.region}::/tags/*",
    ]
  }

  statement {
    sid = "ManageProjectLogGroups"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
      "logs:ListTagsLogGroup",
    ]
    resources = local.log_group_arns
  }

  statement {
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*"]
  }

  # Required by API Gateway HTTP API access logging (vended log delivery).
  # These actions do not support resource-level permissions.
  statement {
    sid = "ApiGatewayAccessLogDelivery"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageProjectAlarms"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource",
    ]
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:${local.prefix}-*"]
  }

  statement {
    sid       = "DescribeAlarms"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# Data & identity: S3, ElastiCache, Secrets Manager, workload IAM roles, state
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deployer_data" {
  statement {
    sid = "ManageProjectBuckets"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketTagging",
      "s3:PutLifecycleConfiguration",
      "s3:Get*",
      "s3:List*",
    ]
    resources = [local.bucket_arn]
  }

  # Lets `terraform destroy` empty versioned buckets (force_destroy).
  statement {
    sid       = "EmptyProjectBucketsOnDestroy"
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = ["${local.bucket_arn}/*"]
  }

  # Not narrowed by s3:prefix: the backend also lists workspace keys ("env:/").
  statement {
    sid       = "TerraformStateList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  # Only the infra/ key prefix: the deployer cannot read or alter bootstrap state.
  statement {
    sid       = "TerraformStateReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/infra/*"]
  }

  statement {
    sid = "ManageProjectElastiCache"
    actions = [
      "elasticache:CreateReplicationGroup",
      "elasticache:ModifyReplicationGroup",
      "elasticache:DeleteReplicationGroup",
      "elasticache:CreateCacheCluster",
      "elasticache:ModifyCacheCluster",
      "elasticache:DeleteCacheCluster",
      "elasticache:CreateCacheSubnetGroup",
      "elasticache:ModifyCacheSubnetGroup",
      "elasticache:DeleteCacheSubnetGroup",
      "elasticache:CreateCacheParameterGroup",
      "elasticache:ModifyCacheParameterGroup",
      "elasticache:ResetCacheParameterGroup",
      "elasticache:DeleteCacheParameterGroup",
      "elasticache:AddTagsToResource",
      "elasticache:RemoveTagsFromResource",
    ]
    resources = [local.elasticache_arn]
  }

  statement {
    sid       = "ElastiCacheReadOnly"
    actions   = ["elasticache:Describe*", "elasticache:ListTagsForResource"]
    resources = ["*"]
  }

  statement {
    sid = "ManageProjectSecrets"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:GetResourcePolicy",
    ]
    resources = [local.secret_arn]
  }

  # Workload roles may only be created/changed with the boundary attached,
  # and only under the project IAM path.
  statement {
    sid       = "CreateAndEditWorkloadRolesWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy"]
    resources = [local.workload_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  statement {
    sid = "ManageWorkloadRoles"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:DeleteRole",
    ]
    resources = [local.workload_role_arn]
  }

  statement {
    sid       = "ReadBoundaryPolicy"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = [aws_iam_policy.workload_boundary.arn]
  }

  # Defense in depth: explicit denies win over any future accidental allow.
  statement {
    sid    = "DenyBootstrapIdentityChanges"
    effect = "Deny"
    actions = [
      "iam:Create*", "iam:Delete*", "iam:Put*", "iam:Update*", "iam:Attach*", "iam:Detach*",
      "iam:Tag*", "iam:Untag*", "iam:Add*", "iam:Remove*", "iam:SetDefaultPolicyVersion",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role${local.bootstrap_iam_path}*",
      "arn:${local.partition}:iam::${local.account_id}:policy${local.bootstrap_iam_path}*",
      "arn:${local.partition}:iam::${local.account_id}:user${local.bootstrap_iam_path}*",
      "arn:${local.partition}:iam::${local.account_id}:group${local.bootstrap_iam_path}*",
    ]
  }

  statement {
    sid       = "DenyBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# Permissions boundary: the maximum any workload role can ever be granted.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid       = "ProjectObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]
  }

  statement {
    sid       = "ProjectLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [for arn in local.log_group_arns : "${arn}:*"]
  }

  # Lambda VPC networking (same set as AWSLambdaVPCAccessExecutionRole).
  statement {
    sid = "LambdaVpcNetworking"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSubnets",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ProjectSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.secret_arn]
  }

  statement {
    sid       = "Tracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}
