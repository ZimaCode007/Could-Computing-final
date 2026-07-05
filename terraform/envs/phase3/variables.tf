variable "region" {
  type    = string
  default = "us-east-1"
}

variable "az_a" {
  description = "AZ matching Phase 2's existing public subnet"
  type        = string
  default     = "us-east-1a"
}

variable "az_b" {
  description = "Second AZ, required for the RDS subnet group and future ALB"
  type        = string
  default     = "us-east-1b"
}

variable "public_subnet_b_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for the web tier (DB now lives on RDS)"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  type    = string
  default = null
}

variable "allowed_ssh_cidr" {
  type = string
}

variable "allowed_http_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "db_username" {
  description = "Must match what the app code expects (originally 'nodeapp' in the Phase 2 script)"
  type        = string
  default     = "nodeapp"
}

variable "db_name" {
  type    = string
  default = "STUDENTS"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "secret_name" {
  description = "Secrets Manager secret name the app code reads at startup (hardcoded as 'Mydbsecret' per the assignment's Cloud9 script)"
  type        = string
  default     = "Mydbsecret"
}

variable "cloud9_instance_type" {
  type    = string
  default = "t3.micro"
}
