output "web_public_ip" {
  value = module.web.public_ip
}

output "web_url" {
  value = "http://${module.web.public_ip}"
}

output "rds_endpoint" {
  value = module.database.endpoint
}

output "rds_address" {
  value = module.database.address
}

output "secret_name" {
  value = module.db_secret.secret_name
}

output "cloud9_environment_id" {
  value = aws_cloud9_environment_ec2.migration.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Both public subnets in this VPC: Phase 2's original one plus the one Phase 3 added"
  value       = concat(data.terraform_remote_state.phase2.outputs.public_subnet_ids, [aws_subnet.public_b.id])
}

output "vpc_id" {
  value = local.vpc_id
}

output "web_sg_id" {
  value = module.web_sg.security_group_id
}

output "db_sg_id" {
  description = "Referenced by Phase 4 to allow the ASG's security group to reach RDS"
  value       = module.db_sg.security_group_id
}
