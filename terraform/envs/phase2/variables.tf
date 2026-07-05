variable "region" {
  description = "AWS region (assignment requires us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "az" {
  description = "Availability zone for the single public subnet"
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the all-in-one POC (app + local MySQL)"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH access (e.g. vockey in AWS Academy). Set to null to skip SSH."
  type        = string
  default     = null
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the instance. Restrict this to your own IP, e.g. 1.2.3.4/32."
  type        = string
}

variable "allowed_http_cidr" {
  description = "CIDR allowed to reach the web app on port 80. The assignment requires public internet access, so this stays open."
  type        = string
  default     = "0.0.0.0/0"
}
