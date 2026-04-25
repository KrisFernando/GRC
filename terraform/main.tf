# GigaChad GRC Platform - AWS Infrastructure
# This Terraform configuration deploys the complete GRC platform to AWS

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.34"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # S3 backend — bucket and DynamoDB table created by CloudFormation prior to terraform init
  backend "s3" {
    bucket         = "gigachad-grc-terraform-state"
    key            = "gigachad-grc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "GigaChad-GRC"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
  # Compute Keycloak URL from ALB DNS when not explicitly set in tfvars.
  # Keycloak is deployed at /auth on the same ALB as the frontend.
  keycloak_url = var.keycloak_url != "" ? var.keycloak_url : (
    var.enable_https
      ? "https://${module.alb.alb_dns_name}/auth"
      : "http://${module.alb.alb_dns_name}/auth"
  )
}

# VPC and Networking
module "vpc" {
  source = "./modules/vpc"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway

  tags = local.common_tags
}

# Security Groups
module "security_groups" {
  source = "./modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id

  allowed_cidr_blocks = var.allowed_cidr_blocks

  tags = local.common_tags
}

# Application Load Balancer
module "alb" {
  source = "./modules/alb"

  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.security_groups.alb_security_group_id]

  certificate_arn = var.ssl_certificate_arn
  enable_https    = var.enable_https

  tags = local.common_tags
}

# RDS PostgreSQL Database
module "rds" {
  source = "./modules/rds"

  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.rds_security_group_id]

  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage

  database_name   = var.database_name
  master_username = var.database_username
  master_password = var.database_password

  backup_retention_period = var.rds_backup_retention_period
  multi_az                = var.rds_multi_az

  tags = local.common_tags
}

# ElastiCache Redis
module "redis" {
  source = "./modules/redis"

  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.redis_security_group_id]

  node_type       = var.redis_node_type
  num_cache_nodes = var.redis_num_cache_nodes
  engine_version  = var.redis_engine_version

  tags = local.common_tags
}

# S3 Bucket for File Storage
module "s3" {
  source = "./modules/s3"

  name_prefix   = local.name_prefix
  random_suffix = random_id.suffix.hex

  enable_versioning = var.s3_enable_versioning
  lifecycle_rules   = var.s3_lifecycle_rules

  tags = local.common_tags
}

# AWS Secrets Manager — stores all sensitive credentials
module "secrets" {
  source = "./modules/secrets"

  name_prefix = local.name_prefix
  environment = var.environment

  database_username = var.database_username
  database_password = var.database_password
  database_host     = module.rds.endpoint
  database_port     = module.rds.port
  database_name     = var.database_name

  redis_host     = module.redis.endpoint
  redis_port     = module.redis.port
  redis_password = module.redis.auth_token

  keycloak_url            = local.keycloak_url
  keycloak_realm          = var.keycloak_realm
  keycloak_client_id      = var.keycloak_client_id
  keycloak_client_secret  = var.keycloak_client_secret
  keycloak_admin_password = var.keycloak_admin_password

  jwt_secret      = var.jwt_secret
  encryption_key  = var.encryption_key
  session_secret  = var.session_secret

  s3_bucket_name = module.s3.bucket_name
  s3_access_key  = ""
  s3_secret_key  = ""
}

# ECS Cluster and Services
module "ecs" {
  source = "./modules/ecs"

  name_prefix        = local.name_prefix
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.ecs_security_group_id]

  # ALB — only frontend gets a target group; backends use Cloud Map DNS via nginx
  alb_target_group_arns = module.alb.target_group_arns_map

  # Secret ARNs for ECS task execution role
  database_secret_arn = module.secrets.database_secret_arn
  keycloak_secret_arn = module.secrets.keycloak_secret_arn
  kms_key_arns        = compact([module.secrets.kms_key_arn])

  # Database configuration
  database_host     = module.rds.endpoint
  database_port     = module.rds.port
  database_name     = var.database_name
  database_username = var.database_username
  database_password = var.database_password

  # Redis configuration
  redis_host = module.redis.endpoint
  redis_port = module.redis.port

  # S3 configuration
  s3_bucket_name = module.s3.bucket_name
  s3_bucket_arn  = module.s3.bucket_arn

  # Container images
  container_registry = var.container_registry
  image_tag          = var.image_tag

  # Service sizing
  service_desired_count = var.ecs_service_desired_count
  task_cpu              = var.ecs_task_cpu
  task_memory           = var.ecs_task_memory

  # Keycloak configuration
  keycloak_url           = local.keycloak_url
  keycloak_realm         = var.keycloak_realm
  keycloak_client_id     = var.keycloak_client_id
  keycloak_client_secret = var.keycloak_client_secret
}

# Keycloak Identity Provider — ECS Fargate service with path-based ALB routing
module "keycloak" {
  source = "./modules/keycloak"

  name_prefix        = local.name_prefix
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.ecs_security_group_id]

  ecs_cluster_arn                = module.ecs.cluster_arn
  service_discovery_namespace_id = module.ecs.service_discovery_namespace_id

  listener_http_arn  = module.alb.listener_http_arn
  listener_https_arn = module.alb.listener_https_arn
  enable_https       = var.enable_https

  database_host     = module.rds.endpoint
  database_port     = module.rds.port
  database_name     = var.database_name
  database_username = var.database_username
  database_password = var.database_password

  container_registry = var.container_registry
  image_tag          = var.image_tag

  task_cpu      = var.keycloak_task_cpu
  task_memory   = var.keycloak_task_memory
  desired_count = var.keycloak_desired_count

  keycloak_admin_password    = var.keycloak_admin_password
  keycloak_client_secret     = var.keycloak_client_secret
  keycloak_mcp_client_secret = var.keycloak_mcp_client_secret
}

# Observability — CloudWatch dashboards, alarms, and log groups
module "observability" {
  source = "./modules/observability"

  name_prefix = local.name_prefix
  environment = var.environment
  aws_region  = var.aws_region
  vpc_id      = module.vpc.vpc_id

  ecs_cluster_name = module.ecs.cluster_name
  rds_instance_id  = module.rds.instance_id
  alb_arn_suffix   = module.alb.alb_arn_suffix

  kms_key_arn = module.secrets.kms_key_arn
  alarm_email = var.alarm_email
}
