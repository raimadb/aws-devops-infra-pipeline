output "db_username_param" {
  value = aws_ssm_parameter.db_username.name
}

output "db_password_param" {
  value = aws_ssm_parameter.db_password.name
}
