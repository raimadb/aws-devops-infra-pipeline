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
    key            = "dev/terraform.tfstate"
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

  vpc_cidr              = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  availability_zones    = var.availability_zones
  environment           = var.environment
}

module "security_groups" {
  source = "../../modules/security-groups"

  vpc_id       = module.vpc.vpc_id
  environment  = var.environment
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
