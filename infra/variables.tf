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

variable "availability_zones" {
  description = "AZs to spread subnets across (high availability)."
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet ranges, one per AZ (same order as availability_zones)."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet ranges, one per AZ (same order as availability_zones)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}
