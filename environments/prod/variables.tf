variable "aws_region" {
  description = "Target aws region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "team-train"
}

variable "environment" {
  description = "Target deployment environment"
  type        = string
  default     = "prod"
}

variable "developer_ips" {
  description = "Allowed public IP list for EKS cluster API access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# DB 관련
variable "db_admin_user" {
  description = "Database admin username"
  type        = string
  default     = "admin"
}

variable "aurora_endpoint" {
  description = "Aurora cluster endpoint"
  type        = string
  default     = ""
}

variable "redis_auth_token" {
  description = "Redis authentication token"
  type        = string
  sensitive   = true
  default     = "SecureRedisToken123!"
}

# Azure 관련
variable "azure_db_endpoint" {
  description = "Azure database endpoint"
  type        = string
  default     = ""
}

variable "azure_db_user" {
  description = "Azure database username"
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Notification receiver email"
  type        = string
  default     = "hajin0533@gmail.com"
}

variable "verified_email_or_domain" {
  description = "Verified SES sender email or domain"
  type        = string
  default     = "hajin0533@gmail.com"
}

variable "azure_vnet_cidr" {
  description = "Azure VNet CIDR block for S2S VPN"
  type        = string
  default     = ""
}



# ==================
# SES Email 발송
# ==================
variable "domain_name" {
  type        = string
  default     = "team-train.cloud"
  description = "SES 이메일 발송에 사용할 도메인"
}

# ==================
# EKS admin 권한
# ==================
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

# ==================
# Route53 API Failover
# ==================
variable "azure_app_service_hostname" {
  description = "azure-app-service 모듈(별도 azure-prod 스택)의 app_service_default_hostname output 값 - Secondary Failover 대상"
  type        = string
  default     = ""
}

