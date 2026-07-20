# CloudTrail 로그 저장용 S3 버킷
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-${var.environment}-cloudtrail-logs"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-cloudtrail-logs"
    Environment = var.environment
  }
}

# S3 버킷 퍼블릭 접근 차단
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 버킷 암호화 (KMS)
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

# S3 버킷 정책 (CloudTrail만 접근 허용)
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudTrail KMS 키 정책
resource "aws_kms_key_policy" "cloudtrail" {
  key_id = aws_kms_key.s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# 현재 AWS 계정 정보
data "aws_caller_identity" "current" {}

# CloudTrail 생성
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  kms_key_id                    = aws_kms_key.s3.arn
  include_global_service_events = true
  is_multi_region_trail         = var.cloudtrail_multi_region
  enable_log_file_validation    = var.cloudtrail_enable_log_validation

  # 보안 이벤트 실시간 탐지를 위해 CloudWatch Logs로도 전송 (관리 이벤트만이라 비용 부담 적음)
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cloudwatch.arn

  # =========================================================================
  # [비용 최적화] 관리 이벤트(Management)만 남기고 데이터 이벤트(S3, Lambda) 제거
  # =========================================================================
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name        = "${var.project_name}-trail"
    Environment = var.environment
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail
  ]
}

# =========================================================================
# CloudTrail -> CloudWatch Logs 연동 (Glue Crawler 대신 실시간 보안 탐지용)
# =========================================================================
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-cloudtrail-logs"
    Environment = var.environment
  }
}

resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  name = "${var.project_name}-${var.environment}-cloudtrail-to-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-cloudtrail-to-cloudwatch-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch" {
  name = "${var.project_name}-${var.environment}-cloudtrail-to-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_to_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# =========================================================================
# 보안 알림용 SNS 토픽 (slack-alerting/notification 모듈의 알람과는 별개 - 보안 이벤트 전용)
# =========================================================================
resource "aws_sns_topic" "security_alerts" {
  name = "${var.project_name}-${var.environment}-security-alerts"

  tags = {
    Name        = "${var.project_name}-security-alerts"
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "security_alerts_email" {
  count     = var.security_alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# =========================================================================
# 보안 이벤트 Metric Filter + Alarm (CIS AWS Foundations Benchmark 기준)
# =========================================================================

# 1. 루트 계정 사용 감지
resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  name           = "${var.project_name}-${var.environment}-root-account-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name      = "RootAccountUsageCount"
    namespace = "${var.project_name}/${var.environment}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "${var.project_name}-${var.environment}-root-account-usage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.root_usage.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.root_usage.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "루트 계정으로 AWS API/콘솔 접근이 감지되었습니다."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

# 2. IAM 정책/권한 변경 감지
resource "aws_cloudwatch_log_metric_filter" "iam_policy_change" {
  name           = "${var.project_name}-${var.environment}-iam-policy-change"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{($.eventName=DeleteGroupPolicy)||($.eventName=DeleteRolePolicy)||($.eventName=DeleteUserPolicy)||($.eventName=PutGroupPolicy)||($.eventName=PutRolePolicy)||($.eventName=PutUserPolicy)||($.eventName=CreatePolicy)||($.eventName=DeletePolicy)||($.eventName=CreatePolicyVersion)||($.eventName=DeletePolicyVersion)||($.eventName=AttachRolePolicy)||($.eventName=DetachRolePolicy)||($.eventName=AttachUserPolicy)||($.eventName=DetachUserPolicy)||($.eventName=AttachGroupPolicy)||($.eventName=DetachGroupPolicy)}"

  metric_transformation {
    name      = "IAMPolicyChangeCount"
    namespace = "${var.project_name}/${var.environment}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "iam_policy_change" {
  alarm_name          = "${var.project_name}-${var.environment}-iam-policy-change"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.iam_policy_change.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.iam_policy_change.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "IAM 정책/권한 변경이 감지되었습니다."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

# 3. 보안그룹 변경 감지
resource "aws_cloudwatch_log_metric_filter" "sg_change" {
  name           = "${var.project_name}-${var.environment}-security-group-change"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }"

  metric_transformation {
    name      = "SecurityGroupChangeCount"
    namespace = "${var.project_name}/${var.environment}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "sg_change" {
  alarm_name          = "${var.project_name}-${var.environment}-security-group-change"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.sg_change.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.sg_change.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "보안그룹 인바운드/아웃바운드 규칙 변경이 감지되었습니다."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

# 4. CloudTrail 자체 변경/중지 감지 (공격자가 흔적을 지우려 할 때 제일 먼저 노리는 지점)
resource "aws_cloudwatch_log_metric_filter" "cloudtrail_tamper" {
  name           = "${var.project_name}-${var.environment}-cloudtrail-tamper"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = StopLogging) || ($.eventName = DeleteTrail) || ($.eventName = UpdateTrail) }"

  metric_transformation {
    name      = "CloudTrailTamperCount"
    namespace = "${var.project_name}/${var.environment}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_tamper" {
  alarm_name          = "${var.project_name}-${var.environment}-cloudtrail-tamper"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.cloudtrail_tamper.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.cloudtrail_tamper.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "CloudTrail이 중지/삭제/수정되었습니다 - 로그 조작 시도일 수 있습니다."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}

