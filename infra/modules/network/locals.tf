locals {
  # Keyed by AZ letter ("a", "b", ...) so names and addresses stay readable
  # and adding or removing an AZ does not shift the other subnets.
  az_keys = [for az in var.availability_zones : substr(az, length(az) - 1, 1)]

  public_subnets = {
    for i, key in local.az_keys : key => {
      az   = var.availability_zones[i]
      cidr = var.public_subnet_cidrs[i]
    }
  }

  private_subnets = {
    for i, key in local.az_keys : key => {
      az   = var.availability_zones[i]
      cidr = var.private_subnet_cidrs[i]
    }
  }
}
