# ALB Module - Application Load Balancer

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.subnet_ids

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-alb"
    }
  )
}

# Single target group for the frontend container (nginx on port 80)
# Nginx handles all API proxying to backend services via Cloud Map DNS
resource "aws_lb_target_group" "frontend" {
  name        = "${var.name_prefix}-tg-frontend"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-tg-frontend"
    }
  )
}

# HTTP Listener: redirect to HTTPS when enabled, otherwise forward to frontend TG
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.enable_https ? [] : [1]
      content {
        target_group {
          arn = aws_lb_target_group.frontend.arn
        }
      }
    }
  }
}

# HTTPS Listener: terminates TLS, forwards plain HTTP to frontend TG
resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}
