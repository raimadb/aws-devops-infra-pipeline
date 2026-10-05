variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "availability_zones" {
  type = list(string)
}

variable "environment" {
  type = string
}

variable "db_username" {
  type        = string
  description = "Master username for the RDS instance"
}
