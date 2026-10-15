variable "project_name" {
  description = "Prefix for every resource name. The deployer role can only manage resources that carry this prefix."
  type        = string
  default     = "sre-assessment"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 chars: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "aws_region" {
  description = "Only region the deployer role is allowed to operate in. Must be the project's region: the account SCP only allows global services in us-east-1."
  type        = string
  default     = "us-east-2"
}

variable "deployer_user_name" {
  description = "Programmatic IAM user whose only permission is assuming the deployer role."
  type        = string
  default     = "terraform-deployer"
}

variable "deployer_session_duration_seconds" {
  description = "Max lifetime of the temporary credentials issued by the deployer role."
  type        = number
  default     = 3600

  validation {
    condition     = var.deployer_session_duration_seconds >= 900 && var.deployer_session_duration_seconds <= 43200
    error_message = "Must be between 900 and 43200 seconds."
  }
}

variable "create_elasticache_service_linked_role" {
  description = "Create AWSServiceRoleForElastiCache. Set to false if it already exists in the account."
  type        = bool
  default     = true
}

variable "state_noncurrent_version_retention_days" {
  description = "Days to keep previous versions of Terraform state files."
  type        = number
  default     = 90
}
