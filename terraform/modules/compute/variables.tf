variable "name" {
  description = "Name tag for the instance"
  type        = string
}

variable "ami_id" {
  description = "AMI ID to launch"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet to launch the instance in"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs to attach"
  type        = list(string)
}

variable "key_name" {
  description = "EC2 key pair name for SSH access. Leave null to launch without one."
  type        = string
  default     = null
}

variable "associate_public_ip" {
  description = "Whether to assign a public IP"
  type        = bool
  default     = true
}

variable "iam_instance_profile" {
  description = "IAM instance profile name to attach (e.g. the lab's existing LabInstanceProfile)"
  type        = string
  default     = null
}

variable "user_data" {
  description = "User data script content"
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags to merge onto the instance"
  type        = map(string)
  default     = {}
}
