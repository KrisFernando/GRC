output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

# Alias used by root outputs.tf
output "dns_name" {
  description = "DNS name of the ALB (alias for alb_dns_name)"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB (used for CloudWatch metrics)"
  value       = aws_lb.main.arn_suffix
}

output "frontend_target_group_arn" {
  description = "ARN of the frontend target group"
  value       = aws_lb_target_group.frontend.arn
}

# Map passed to the ECS module — only frontend has an ALB target group;
# backend services are reached exclusively via Cloud Map service discovery
output "target_group_arns_map" {
  description = "Map of service name to ALB target group ARN"
  value = {
    frontend   = aws_lb_target_group.frontend.arn
    controls   = ""
    frameworks = ""
    policies   = ""
    tprm       = ""
    trust      = ""
    audit      = ""
  }
}

output "listener_http_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "listener_https_arn" {
  description = "ARN of the HTTPS listener (null when HTTPS disabled)"
  value       = var.enable_https ? aws_lb_listener.https[0].arn : null
}
