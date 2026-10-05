variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "target_port" {
  type    = number
  default = 8000
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "log_expiration_days" {
  type    = number
  default = 14
}

variable "elb_account_id" {
  type        = string
  description = "AWS-owned account ID that the regional ELB log-delivery service uses to write access logs. Region-specific; this project is pinned to ap-south-1 (Mumbai), whose ELB log account is 718504428378. Revisit if the project ever spans another region."
  default     = "718504428378"
}
