variable "environment" {
  type = string
}

variable "force_delete" {
  type        = bool
  default     = false
  description = "Allow terraform destroy to delete the repo even if it holds images"
}

variable "image_retention_count" {
  type    = number
  default = 10
}
