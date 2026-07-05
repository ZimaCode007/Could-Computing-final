output "vpc_id" {
  description = "VPC ID, referenced by Phase 3 via terraform_remote_state"
  value       = module.network.vpc_id
}

output "igw_id" {
  description = "Internet Gateway ID, referenced by Phase 3 via terraform_remote_state"
  value       = module.network.igw_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "web_public_ip" {
  description = "Public IPv4 address of the all-in-one web/DB instance"
  value       = module.web.public_ip
}

output "web_url" {
  description = "URL to access the student records web app"
  value       = "http://${module.web.public_ip}"
}
