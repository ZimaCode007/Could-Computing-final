variable "name" {
  description = "Name of the security group"
  type        = string
}

variable "description" {
  description = "Description of the security group"
  type        = string
  default     = "Managed by Terraform"
}

variable "vpc_id" {
  description = "VPC to create the security group in"
  type        = string
}

variable "cidr_ingress_rules" {
  description = "Ingress rules sourced from CIDR blocks"
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "sg_ingress_rules" {
  description = "Ingress rules sourced from another security group (e.g. allow the DB port only from the web tier's SG)"
  type = list(object({
    description              = string
    from_port                = number
    to_port                  = number
    protocol                 = string
    source_security_group_id = string
  }))
  default = []
}
