variable "name_prefix" {
  description = "Prefix for naming resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for ECS tasks"
  type        = list(string)
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster to run Keycloak in"
  type        = string
}

variable "service_discovery_namespace_id" {
  description = "Cloud Map private DNS namespace ID (from ECS module)"
  type        = string
}

variable "listener_http_arn" {
  description = "ALB HTTP listener ARN (used for path rule when HTTPS disabled)"
  type        = string
}

variable "listener_https_arn" {
  description = "ALB HTTPS listener ARN (null when enable_https = false)"
  type        = string
  default     = null
}

variable "enable_https" {
  description = "Whether HTTPS is enabled on the ALB"
  type        = bool
}

variable "database_host" {
  description = "RDS PostgreSQL hostname"
  type        = string
}

variable "database_port" {
  description = "RDS PostgreSQL port"
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "PostgreSQL database name (Keycloak uses schema isolation within this DB)"
  type        = string
}

variable "database_username" {
  description = "PostgreSQL master username"
  type        = string
  sensitive   = true
}

variable "database_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "container_registry" {
  description = "ECR registry URL (e.g., ACCOUNT.dkr.ecr.REGION.amazonaws.com)"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "task_cpu" {
  description = "Fargate CPU units for Keycloak (512 = 0.5 vCPU)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate memory in MB for Keycloak"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Number of Keycloak task instances to run"
  type        = number
  default     = 1
}

variable "keycloak_admin_username" {
  description = "Keycloak bootstrap admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak bootstrap admin password"
  type        = string
  sensitive   = true
}

variable "keycloak_http_relative_path" {
  description = "Keycloak base path (KC_HTTP_RELATIVE_PATH)"
  type        = string
  default     = "/auth"
}

variable "keycloak_client_secret" {
  description = "Secret for the grc-services client — injected as GRC_SERVICES_SECRET into the realm template"
  type        = string
  sensitive   = true
}

variable "keycloak_mcp_client_secret" {
  description = "Secret for the grc-mcp client — injected as GRC_MCP_SECRET into the realm template"
  type        = string
  sensitive   = true
}
