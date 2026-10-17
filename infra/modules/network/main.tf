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

# "Public" and "private" are defined by their route tables, not by the subnet.
# No subnet hands out public IPs: the only public IP is the NAT's Elastic IP.
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-public-${each.key}"
    Tier = "public"
  }
}

# Lambda and Redis live here: no direct route from or to the internet.
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-private-${each.key}"
    Tier = "private"
  }
}
