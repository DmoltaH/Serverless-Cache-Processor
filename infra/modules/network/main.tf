# Private network for Lambda and Redis. Nothing enters or leaves a VPC until
# gateways/endpoints are added explicitly. See README.md for the rationale.
resource "aws_vpc" "this" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"

  # Redis and the S3 endpoint are reached by DNS name from inside the VPC.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}
