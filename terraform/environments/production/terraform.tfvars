vpc_cidr                   = "10.2.0.0/16"
public_subnet_cidrs        = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs       = ["10.2.11.0/24", "10.2.12.0/24"]
availability_zones         = ["ap-south-1a", "ap-south-1b"]
environment                = "production"
db_username                = "appadmin"
db_instance_class          = "db.t3.micro"
db_multi_az                = false
db_backup_retention_period = 1

ecr_force_delete  = true
app_cpu           = 256
app_memory        = 512
app_desired_count = 1
