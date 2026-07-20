# CloudFront OAC (S3 접근 제어)
resource "aws_cloudfront_origin_access_control" "main" {
  provider                          = aws.us_east_1
  name                              = "${var.project_name}-oac"
  description                       = "S3 OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Function: /api/* 경로를 백엔드에 맞게 /* 로 재작성
resource "aws_cloudfront_function" "rewrite_api" {
  name    = "${var.project_name}-${var.environment}-rewrite-api"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite /api/health to /health for backend ALB"
  publish = true
  code    = <<-EOT
function handler(event) {
    var request = event.request;
    // 백엔드는 /api/reserve, /api/trains 등으로 라우팅되지만 health만 /health로 설정되어 있으므로 health만 예외 처리
    if (request.uri === '/api/health') {
        request.uri = '/health';
    }
    return request;
}
EOT
}


# CloudFront 배포
resource "aws_cloudfront_distribution" "main" {
  provider = aws.us_east_1

  # S3 오리진 (프론트엔드)
  origin {
    domain_name              = var.s3_frontend_bucket_regional_domain_name
    origin_id                = "S3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  # ALB 오리진 (백엔드 API) - 주소 및 환경에 따라 동적 생성
  dynamic "origin" {
    for_each = (var.environment == "prod" || var.alb_dns_name != "") ? [1] : []
    content {
      domain_name = var.environment == "prod" ? "api.team-train.cloud" : var.alb_dns_name
      origin_id   = "ALB-backend"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = var.environment == "prod" ? "https-only" : "http-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }

      # ALB SG(prefix list)는 "CloudFront에서 왔는지"만 확인하므로, 이 커스텀 헤더로
      # "내 CloudFront 배포가 보낸 게 맞는지"까지 ALB 리스너 규칙에서 추가 검증함
      dynamic "custom_header" {
        for_each = var.origin_verify_secret != "" ? [1] : []
        content {
          name  = "X-Origin-Verify"
          value = var.origin_verify_secret
        }
      }
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  dynamic "logging_config" {
    for_each = var.ops_logs_bucket_domain_name != "" ? [1] : []
    content {
      include_cookies = false
      bucket          = var.ops_logs_bucket_domain_name
      prefix          = "cloudfront/"
    }
  }
  # prod만 도메인 연결 
  aliases = var.environment == "prod" ? [
    "team-train.cloud",
    "www.team-train.cloud"
  ] : []

  # 기본 캐시 동작 (프론트엔드)
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-frontend"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # API 경로 캐시 동작 (백엔드가 존재할 때만 동적 구성)
  dynamic "ordered_cache_behavior" {
    for_each = (var.environment == "prod" || var.alb_dns_name != "") ? [1] : []
    content {
      path_pattern           = "/api/*"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods         = ["GET", "HEAD"]
      target_origin_id       = "ALB-backend"
      viewer_protocol_policy = "redirect-to-https"

      forwarded_values {
        query_string = true
        headers      = ["Authorization", "Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
        cookies {
          forward = "all"
        }
      }

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.rewrite_api.arn
      }

      min_ttl     = 0
      default_ttl = 0
      max_ttl     = 0
    }
  }

  # WAF 연동 (WAF ARN이 있을 때만 연동)
  web_acl_id = var.waf_arn != "" ? var.waf_arn : null

  # SSL 인증서 (prod만 ACM, dev는 기본 인증서) 
  viewer_certificate {
    acm_certificate_arn            = var.environment == "prod" ? var.acm_certificate_arn : null
    ssl_support_method             = var.environment == "prod" ? "sni-only" : null
    minimum_protocol_version       = var.environment == "prod" ? "TLSv1.2_2021" : null
    cloudfront_default_certificate = var.environment == "prod" ? false : true
  }

  # SPA 라우팅 (React)
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "${var.project_name}-cf"
    Environment = var.environment
  }
}

# S3 버킷 정책 (CloudFront만 접근 허용)
resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.s3_frontend_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${var.s3_frontend_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}
