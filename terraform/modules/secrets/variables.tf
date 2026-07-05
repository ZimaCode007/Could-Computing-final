variable "name" {
  description = "Secret name in Secrets Manager"
  type        = string
}

variable "description" {
  type    = string
  default = "Managed by Terraform"
}

variable "secret_string" {
  description = "JSON-encoded secret value, e.g. jsonencode({ user = ..., password = ..., host = ..., db = ... })"
  type        = string
  sensitive   = true
}

variable "recovery_window_in_days" {
  description = "Days AWS keeps the secret recoverable after deletion. 0 deletes immediately, useful for a POC you'll tear down and recreate often."
  type        = number
  default     = 0
}
