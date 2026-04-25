output "service_endpoint" {
  description = "Internal Cloud Map endpoint for Keycloak (for service-to-service communication)"
  value       = "http://keycloak.${var.name_prefix}.local:8080${var.keycloak_http_relative_path}"
}

output "service_arn" {
  description = "ARN of the Keycloak ECS service"
  value       = aws_ecs_service.keycloak.id
}

output "target_group_arn" {
  description = "ARN of the Keycloak ALB target group"
  value       = aws_lb_target_group.keycloak.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the grc-keycloak image"
  value       = aws_ecr_repository.keycloak.repository_url
}

output "log_group_name" {
  description = "CloudWatch log group name for Keycloak"
  value       = aws_cloudwatch_log_group.keycloak.name
}
