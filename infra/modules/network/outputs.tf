output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "IPv4 range of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, one per AZ."
  value       = [for key in local.az_keys : aws_subnet.public[key].id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, one per AZ (Lambda and Redis)."
  value       = [for key in local.az_keys : aws_subnet.private[key].id]
}
