resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/${var.environment}/db/username"
  type  = "String"
  value = var.db_username

  tags = {
    Environment = var.environment
  }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.environment}/db/password"
  type  = "SecureString"
  value = random_password.db_password.result

  tags = {
    Environment = var.environment
  }
}
