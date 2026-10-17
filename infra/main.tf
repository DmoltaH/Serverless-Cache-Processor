module "network" {
  source = "./modules/network"

  name_prefix = var.project_name
  vpc_cidr    = var.vpc_cidr
}
