output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "IPv4 range of the VPC."
  value       = aws_vpc.this.cidr_block
}
