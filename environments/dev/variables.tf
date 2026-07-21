variable "aws_region" {
  description = "Target aws region"
  type        = string
  default     = "ap-northeast-2"
}


variable "project_name" {
  description = "project name"
  type        = string
  default     = "team-train"
}

variable "environment" {
  description = "Target deployment environment"
  type        = string
  default     = "dev"
}

variable "developer_ips" {
  # 기본값을 0.0.0.0/0으로 두면 tfvars 없이 apply할 때 EKS API 서버가 인터넷에 그대로
  # 노출된다. 기본값을 없애 실제 개발자 IP를 명시적으로 넣도록 강제한다.
  description = "EKS 클러스터 API 공개 엔드포인트 접근을 허용할 IP CIDR 목록 (예: [\"1.2.3.4/32\"]) - tfvars로 반드시 지정"
  type        = list(string)
}

# Redis AUTH 토큰 (16자 이상 필수)
variable "redis_auth_token" {
  description = "Redis AUTH Token for ElastiCache"
  type        = string
  sensitive   = true
  default     = "SecureRedisToken123!"
}

# DB 관련 변수 선언
variable "db_admin_user" {
  description = "admin user data"
  type        = string
  default     = "admin"
}

variable "db_admin_password" {
  description = "admin user password"
  type        = string
  default     = "Admin123!@#"
}

variable "azure_db_endpoint" {
  description = "azure database endpoint"
  type        = string
  default     = "dummy.azure.endpoint"
}

variable "azure_db_user" {
  description = "azure database user"
  type        = string
  default     = "admin"
}

variable "azure_db_password" {
  description = "azure database password"
  type        = string
  sensitive   = true
  default     = "Admin123!@#"
}

# 내부 알림용
variable "notification_email" {
  description = "CloudWatch Alarm Email"
  type        = string
  default     = "hajin0533@gmail.com"
}

variable "verified_email_or_domain" {
  description = "SES Sender Email"
  type        = string
  default     = "hajin0533@gmail.com"
}

variable "eks_admin_principal_arns" {
  description = "EKS 클러스터 admin 권한을 부여할 IAM Role/User ARN 목록 (계정 root 통짜 부여 금지)"
  type        = list(string)
  default     = []
}

variable "security_alert_email" {
  description = "루트계정 사용/IAM 변경/보안그룹 변경/CloudTrail 조작 알람을 받을 이메일"
  type        = string
  default     = ""
}
