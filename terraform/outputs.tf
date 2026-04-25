# GigaChad GRC Platform - Terraform Outputs

output "application_url" {
  description = "URL to access the GRC application"
  value       = var.enable_https ? "https://${module.alb.alb_dns_name}" : "http://${module.alb.alb_dns_name}"
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = module.alb.alb_dns_name
}

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = module.rds.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.redis.endpoint
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 bucket name for file storage"
  value       = module.s3.bucket_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "keycloak_url" {
  description = "Keycloak admin console and auth URL"
  value       = local.keycloak_url
}

output "keycloak_ecr_url" {
  description = "ECR repository URL for the Keycloak image (push grc-keycloak here)"
  value       = module.keycloak.ecr_repository_url
}

output "deployment_instructions" {
  description = "Post-deployment instructions"
  value       = <<-EOT
    GigaChad GRC Platform has been deployed successfully!

    Next steps:
    1. Point your domain to the load balancer: ${module.alb.alb_dns_name}
    2. Access the application at: ${var.enable_https ? "https" : "http"}://${module.alb.alb_dns_name}
    3. Keycloak admin console: ${local.keycloak_url}/admin (user: admin)
    4. Run database migrations (see docs/deployment.md)
    5. Create your first organization and admin user

    For detailed post-deployment steps, see: docs/post-deployment.md
  EOT
}
