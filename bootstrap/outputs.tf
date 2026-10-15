output "state_bucket_name" {
  description = "S3 bucket holding Terraform state."
  value       = aws_s3_bucket.state.bucket
}

output "deployer_user_name" {
  description = "Create an access key for this user in the console (never in Terraform: it would land in state)."
  value       = aws_iam_user.deployer.name
}

output "deployer_role_arn" {
  description = "Role assumed by Terraform for the infra/ stack."
  value       = aws_iam_role.deployer.arn
}

output "workload_boundary_arn" {
  description = "Permissions boundary that infra/ must attach to every role it creates."
  value       = aws_iam_policy.workload_boundary.arn
}

output "aws_cli_config" {
  description = "Append to ~/.aws/config on your workstation."
  value       = <<-EOT
    [profile deployer-user]
    region = ${local.region}

    [profile deployer-role]
    role_arn          = ${aws_iam_role.deployer.arn}
    source_profile    = deployer-user
    role_session_name = terraform-${local.prefix}
    region            = ${local.region}
  EOT
}
