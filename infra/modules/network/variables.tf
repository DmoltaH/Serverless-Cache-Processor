variable "name_prefix" {
  description = "Prefix for resource names (Name tags)."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 address range of the VPC, e.g. 10.0.0.0/16."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}
