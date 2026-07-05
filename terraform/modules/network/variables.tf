variable "name_prefix" {
  description = "Prefix applied to all resource names/tags created by this module"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across, matched by index to the CIDR lists"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ, in order)"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ, in order). Leave empty for phases without a private tier."
  type        = list(string)
  default     = []
}
