# ALB 생성
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  # ALB 액세스 로그 → ops-logs S3 버킷
  access_logs {
    bucket  = var.ops_logs_bucket_id
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb"
    Environment = var.environment
  }
}

# HTTP 리스너
# dev  → 80포트 그대로 Target Group으로 forward
# prod → 443으로 리다이렉트
resource "aws_lb_listener" "front_http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.environment == "dev" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.app_tg.arn
    }
  }
}

# HTTPS 리스너 - prod만 생성
# origin_verify_secret이 설정되면 기본은 차단(403)하고, 커스텀 헤더가 일치하는
# 요청만 아래 리스너 규칙에서 통과시킴 (prefix list는 "CloudFront에서 왔는지"만
# 확인하므로, 이 헤더로 "내 CloudFront 배포가 보낸 게 맞는지"까지 추가 검증)
resource "aws_lb_listener" "front_https" {
  count             = var.environment == "prod" ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_alb_certificate_arn

  dynamic "default_action" {
    for_each = var.origin_verify_secret != "" ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Forbidden"
        status_code  = "403"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.origin_verify_secret == "" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.app_tg.arn
    }
  }
}

resource "aws_lb_listener_rule" "verified_origin" {
  count        = var.environment == "prod" && var.origin_verify_secret != "" ? 1 : 0
  listener_arn = aws_lb_listener.front_https[0].arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_secret]
    }
  }
}

# Target Group
# TargetGroupBinding 방식으로 ALB Controller가 Pod IP 자동 등록
resource "aws_lb_target_group" "app_tg" {
  name        = "${var.project_name}-${var.environment}-app-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-tg"
    Environment = var.environment
  }
}