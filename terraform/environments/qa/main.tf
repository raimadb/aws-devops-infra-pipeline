terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket         = "my-tf-106834-bucket"
    key            = "qa/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "my-dynamo-106834-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
}

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  environment          = var.environment
}

module "security_groups" {
  source = "../../modules/security-groups"

  vpc_id      = module.vpc.vpc_id
  environment = var.environment
}

module "secrets" {
  source = "../../modules/secrets"

  db_username = var.db_username
  environment = var.environment
}

module "rds" {
  source = "../../modules/rds"

  environment             = var.environment
  private_subnet_ids      = module.vpc.private_subnet_ids
  rds_sg_id               = module.security_groups.rds_sg_id
  db_username_param       = module.secrets.db_username_param
  db_password_param       = module.secrets.db_password_param
  instance_class          = var.db_instance_class
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
}

module "alb" {
  source = "../../modules/alb"

  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
}

module "ecr" {
  source = "../../modules/ecr"

  environment  = var.environment
  force_delete = var.ecr_force_delete
}

module "compute" {
  source = "../../modules/compute"

  environment        = var.environment
  private_subnet_ids = module.vpc.private_subnet_ids
  app_sg_id          = module.security_groups.app_sg_id
  target_group_arn   = module.alb.target_group_arn
  ecr_repository_url = module.ecr.repository_url
  image_tag          = var.image_tag
  db_host            = module.rds.db_address
  db_port            = module.rds.db_port
  db_name            = module.rds.db_name
  db_username_param  = module.secrets.db_username_param
  db_password_param  = module.secrets.db_password_param
  cpu                = var.app_cpu
  memory             = var.app_memory
  desired_count      = var.app_desired_count
}

module "monitoring" {
  source = "../../modules/monitoring"

  environment      = var.environment
  cluster_name     = module.compute.cluster_name
  service_name     = module.compute.service_name
  log_group_name   = module.compute.log_group_name
  alb_arn_suffix   = module.alb.alb_arn_suffix
  target_group_arn = module.alb.target_group_arn
  db_identifier    = module.rds.db_identifier
}
