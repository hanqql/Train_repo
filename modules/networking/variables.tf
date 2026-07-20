variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "developer_ips" {
  description = "List of developer IP addresses"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Aurora 완성 후 주석 해제
# variable "db_admin_user" {
#   description = "Database admin username"
#   type        = string
#   default     = ""
# }

# variable "db_admin_password" {
#   description = "Database admin password"
#   type        = string
#   sensitive   = true
#   default     = ""
# }

variable "aurora_endpoint" {
  description = "Aurora cluster endpoint"
  type        = string
  default     = ""
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC Provider ARN"
  type        = string
  default     = ""
}

variable "eks_oidc_provider" {
  description = "EKS OIDC Provider URL"
  type        = string
  default     = ""
}

# ==================
# waf 변수
# ==================
variable "log_retention_days" {
  description = "CloudWatch Log Group retention period in days"
  type        = number
  default     = 7
}


# ==================
# CloudTrail 관련 변수
# ==================
variable "security_alert_email" {
  description = "루트계정 사용/IAM 변경/보안그룹 변경/CloudTrail 조작 알람을 받을 이메일 (비어있으면 구독 생성 안 함)"
  type        = string
  default     = ""
}

variable "cloudtrail_retention_days" {
  description = "Retention period for CloudTrail logs in days"
  type        = number
  default     = 90
}

variable "cloudtrail_enable_log_validation" {
  description = "Whether to enable log file integrity validation for CloudTrail"
  type        = bool
  default     = true
}

variable "cloudtrail_multi_region" {
  description = "Whether the CloudTrail is created for multi-region"
  type        = bool
  default     = true
}

# ==================
# EKS 관련 변수
# EKS 생성 후 주석 해제
# ==================
variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = ""
}

# variable "eks_cluster_endpoint" {
#   description = "The endpoint URL for the EKS cluster API server"
#   type        = string
#   default     = ""
# }

# variable "eks_cluster_ca" {
#   description = "The base64 encoded certificate authority data for the EKS cluster"
#   type        = string
#   default     = ""
# }

# variable "eks_cluster_token" {
#   description = "The authentication token to access the EKS cluster API"
#   type        = string
#   default     = ""
# }

# ==================
# IRSA Pod Role ARN
# EKS 생성 후 주석 해제
# ==================
# variable "booking_pod_role_arn" {
#   description = "IAM Role ARN for the Booking Service Pod"
#   type        = string
#   default     = ""
# }

# variable "user_pod_role_arn" {
#   description = "IAM Role ARN for the User Service Pod"
#   type        = string
#   default     = ""
# }

# variable "payment_pod_role_arn" {
#   description = "IAM Role ARN for the Payment Service Pod"
#   type        = string
#   default     = ""
# }

# ==================
# DB & Redis Subnet
# EKS 생성 후 주석 해제
# ==================
# variable "db_subnet_ids" {
#   description = "List of subnet IDs for DB and ElastiCache subnet groups"
#   type        = list(string)
#   default     = []
# }

variable "single_nat_gateway" {
  description = "Whether to use a single NAT Gateway (true) or one per AZ (false)"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Whether to enable VPC endpoints for AWS services in the VPC"
  type        = bool
  default     = true

}

variable "ops_logs_bucket_domain_name" {
  description = "The domain name of the ops-logs S3 bucket for CloudFront logs"
  type        = string
  default     = ""
}

# ==================
# S2S VPN (Azure DR 연동)
# ==================
variable "azure_vnet_cidr" {
  description = "Azure VNet CIDR block for S2S VPN routing (Aurora -> Azure DMS DR replication)"
  type        = string
  default     = ""
}

variable "azure_vpn_gateway_ip" {
  description = "Azure VPN Gateway public IP. azure-networking 모듈을 먼저 apply 해서 얻은 IP를 입력 (2단계 apply)"
  type        = string
  default     = ""
}
