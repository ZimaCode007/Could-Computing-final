variable "name_prefix" {
  type = string
}

variable "engine" {
  type    = string
  default = "mysql"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type = string
}

variable "username" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

variable "subnet_ids" {
  description = "Private subnet IDs, minimum of two AZs required for the DB subnet group"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  type = list(string)
}

variable "multi_az" {
  description = "Assignment assumption: DB is hosted in a single AZ only"
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds. 0 disables it per the assignment's instructions."
  type        = number
  default     = 0
}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}
