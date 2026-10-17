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

variable "availability_zones" {
  description = "AZs to spread subnets across. One public and one private subnet per AZ."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required for high availability."
  }
}

variable "public_subnet_cidrs" {
  description = "IPv4 range of each public subnet, in the same order as availability_zones."
  type        = list(string)

  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every public subnet CIDR must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "Provide exactly one public subnet CIDR per availability zone."
  }
}

variable "private_subnet_cidrs" {
  description = "IPv4 range of each private subnet, in the same order as availability_zones."
  type        = list(string)

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every private subnet CIDR must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones)
    error_message = "Provide exactly one private subnet CIDR per availability zone."
  }
}
