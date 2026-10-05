output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "alb_sg_id" {
  value = module.security_groups.alb_sg_id
}

output "app_sg_id" {
  value = module.security_groups.app_sg_id
}

output "rds_sg_id" {
  value = module.security_groups.rds_sg_id
}

output "db_username_param" {
  value = module.secrets.db_username_param
}

output "db_password_param" {
  value = module.secrets.db_password_param
}

output "db_address" {
  value = module.rds.db_address
}

output "db_port" {
  value = module.rds.db_port
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "target_group_arn" {
  value = module.alb.target_group_arn
}

output "alb_arn_suffix" {
  value = module.alb.alb_arn_suffix
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = module.compute.cluster_name
}

output "ecs_service_name" {
  value = module.compute.service_name
}

output "app_log_group" {
  value = module.compute.log_group_name
}
