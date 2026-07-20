# =========================================================================
# ALB 전용 Regional WAF
#
# CloudFront WAF(modules/networking/waf.tf)는 CloudFront 경유 트래픽만 봄.
# 만약 커스텀 헤더 검증(X-Origin-Verify)까지 뚫리는 경우를 대비해, ALB에도
# 별도 Regional WAF를 붙여 계층 방어(defense in depth)를 완성함.
# Regional Scope는 CLOUDFRONT와 달리 ALB와 같은 리전에 만들어야 함 (us-east-1 아님).
# =========================================================================
resource "aws_wafv2_web_acl" "alb" {
  count       = var.environment == "prod" && var.enable_alb_waf ? 1 : 0
  name        = "${var.project_name}-${var.environment}-alb-waf"
  description = "ALB 앞단 Regional WAF - 헤더 검증까지 뚫렸을 때의 2차 방어선"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-alb-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-alb-sqli-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # CloudFront WAF와 같은 기준의 Rate Limiting (5분간 IP당 2000회 초과 시 차단)
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-alb-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-alb-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-alb-waf"
    Environment = var.environment
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.environment == "prod" && var.enable_alb_waf ? 1 : 0
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.alb[0].arn
}
