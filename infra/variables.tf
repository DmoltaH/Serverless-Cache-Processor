variable "project_name" {
  description = "Prefix for every resource name. Must match bootstrap/: the deployer role can only manage resources with this prefix."
  type        = string
  default     = "sre-assessment"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 chars: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "aws_region" {
  description = "Region to deploy into. Must be the only region the deployer role is allowed to use."
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "AWS CLI profile that assumes the deployer role."
  type        = string
  default     = "deployer-role"
}

variable "vpc_cidr" {
  description = "IPv4 address range of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}
