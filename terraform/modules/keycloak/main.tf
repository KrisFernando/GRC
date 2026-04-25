# Keycloak ECS Service Module
# Deploys Keycloak 25 as a Fargate service with:
#   - ALB path-based routing at /auth/*
#   - Schema-isolated PostgreSQL (keycloak schema in the shared RDS instance)
#   - Cloud Map registration for internal service discovery
#   - Realm auto-import with secrets substituted at startup via envsubst

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ECR repository for the Keycloak image (built by GitHub Actions)
resource "aws_ecr_repository" "keycloak" {
  name                 = "grc-keycloak"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "grc-keycloak"
    Environment = var.environment
  }
}

resource "aws_ecr_lifecycle_policy" "keycloak" {
  repository = aws_ecr_repository.keycloak.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# CloudWatch log group for Keycloak container output
resource "aws_cloudwatch_log_group" "keycloak" {
  name              = "/ecs/${var.name_prefix}/keycloak"
  retention_in_days = 30

  tags = {
    Name        = "${var.name_prefix}-keycloak-logs"
    Environment = var.environment
  }
}

# Secrets Manager secret for Keycloak startup credentials.
# Holds the admin password, DB password, and both client secrets
# that are injected into the realm template at container startup.
resource "aws_secretsmanager_secret" "keycloak_startup" {
  name                    = "${var.name_prefix}/keycloak-startup"
  description             = "Keycloak startup credentials for GigaChad GRC"
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.name_prefix}-keycloak-startup-secret"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "keycloak_startup" {
  secret_id = aws_secretsmanager_secret.keycloak_startup.id
  secret_string = jsonencode({
    admin_password      = var.keycloak_admin_password
    db_password         = var.database_password
    grc_services_secret = var.keycloak_client_secret
    grc_mcp_secret      = var.keycloak_mcp_client_secret
  })
}

# IAM role for ECS task execution (pulls image, reads secrets, writes logs)
resource "aws_iam_role" "keycloak_execution" {
  name = "${var.name_prefix}-keycloak-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.name_prefix}-keycloak-execution-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "keycloak_execution_managed" {
  role       = aws_iam_role.keycloak_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "keycloak_execution_secrets" {
  name = "${var.name_prefix}-keycloak-execution-secrets"
  role = aws_iam_role.keycloak_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [aws_secretsmanager_secret.keycloak_startup.arn]
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}/*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.name_prefix}/*:log-stream:*"
        ]
      }
    ]
  })
}

# IAM role for the Keycloak container itself (no extra AWS permissions needed)
resource "aws_iam_role" "keycloak_task" {
  name = "${var.name_prefix}-keycloak-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.name_prefix}-keycloak-task-role"
    Environment = var.environment
  }
}

# Cloud Map service registration — internal DNS: keycloak.<name_prefix>.local
resource "aws_service_discovery_service" "keycloak" {
  name = "keycloak"

  dns_config {
    namespace_id   = var.service_discovery_namespace_id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# ALB target group — Keycloak listens on port 8080 (plain HTTP; TLS terminates at ALB)
resource "aws_lb_target_group" "keycloak" {
  name        = "${var.name_prefix}-tg-keycloak"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    path                = "${var.keycloak_http_relative_path}/health/ready"
    matcher             = "200"
  }

  tags = {
    Name        = "${var.name_prefix}-tg-keycloak"
    Environment = var.environment
  }
}

# Listener rule on HTTP listener — only active when HTTPS is disabled
resource "aws_lb_listener_rule" "keycloak_http" {
  count        = var.enable_https ? 0 : 1
  listener_arn = var.listener_http_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.keycloak.arn
  }

  condition {
    path_pattern {
      values = [var.keycloak_http_relative_path, "${var.keycloak_http_relative_path}/*"]
    }
  }
}

# Listener rule on HTTPS listener — active when HTTPS is enabled
resource "aws_lb_listener_rule" "keycloak_https" {
  count        = var.enable_https ? 1 : 0
  listener_arn = var.listener_https_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.keycloak.arn
  }

  condition {
    path_pattern {
      values = [var.keycloak_http_relative_path, "${var.keycloak_http_relative_path}/*"]
    }
  }
}

# ECS task definition for Keycloak
resource "aws_ecs_task_definition" "keycloak" {
  family                   = "${var.name_prefix}-keycloak"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.keycloak_execution.arn
  task_role_arn            = aws_iam_role.keycloak_task.arn

  container_definitions = jsonencode([
    {
      name      = "keycloak"
      image     = "${var.container_registry}/grc-keycloak:${var.image_tag}"
      essential = true

      portMappings = [{ containerPort = 8080, protocol = "tcp" }]

      environment = [
        { name = "KC_DB",                  value = "postgres" },
        { name = "KC_DB_URL",              value = "jdbc:postgresql://${var.database_host}:${var.database_port}/${var.database_name}?currentSchema=keycloak" },
        { name = "KC_DB_USERNAME",         value = var.database_username },
        { name = "KC_DB_SCHEMA",           value = "keycloak" },
        { name = "KC_HTTP_PORT",           value = "8080" },
        { name = "KC_HTTP_RELATIVE_PATH",  value = var.keycloak_http_relative_path },
        { name = "KC_PROXY_HEADERS",       value = "xforwarded" },
        { name = "KC_HOSTNAME_STRICT",     value = "false" },
        { name = "KC_HEALTH_ENABLED",      value = "true" },
        { name = "KEYCLOAK_ADMIN",         value = var.keycloak_admin_username },
        { name = "JAVA_OPTS_APPEND",       value = "-Xms256m -Xmx${var.task_memory - 256}m" },
      ]

      secrets = [
        { name = "KC_DB_PASSWORD",          valueFrom = "${aws_secretsmanager_secret.keycloak_startup.arn}:db_password::" },
        { name = "KEYCLOAK_ADMIN_PASSWORD", valueFrom = "${aws_secretsmanager_secret.keycloak_startup.arn}:admin_password::" },
        { name = "GRC_SERVICES_SECRET",     valueFrom = "${aws_secretsmanager_secret.keycloak_startup.arn}:grc_services_secret::" },
        { name = "GRC_MCP_SECRET",          valueFrom = "${aws_secretsmanager_secret.keycloak_startup.arn}:grc_mcp_secret::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.keycloak.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "keycloak"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://localhost:8080${var.keycloak_http_relative_path}/health/ready || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 5
        startPeriod = 120
      }
    }
  ])

  tags = {
    Name        = "${var.name_prefix}-keycloak"
    Environment = var.environment
  }
}

# ECS service — Fargate, private subnets, behind ALB target group
resource "aws_ecs_service" "keycloak" {
  name            = "${var.name_prefix}-keycloak"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.keycloak.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.keycloak.arn
    container_name   = "keycloak"
    container_port   = 8080
  }

  service_registries {
    registry_arn = aws_service_discovery_service.keycloak.arn
  }

  # Listener rules must exist before the service starts routing traffic
  depends_on = [
    aws_lb_listener_rule.keycloak_http,
    aws_lb_listener_rule.keycloak_https,
  ]

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = {
    Name        = "${var.name_prefix}-keycloak"
    Environment = var.environment
  }
}
