variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "s3_frontend_bucket_id" {
  description = "S3 bucket ID for the frontend"
  type        = string
}

variable "s3_frontend_bucket_arn" {
  description = "S3 bucket ARN for the frontend"
  type        = string
}

variable "s3_frontend_bucket_regional_domain_name" {
  description = "S3 bucket regional domain name for the frontend"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name to route API requests to"
  type        = string
}

variable "origin_verify_secret" {
  description = "CloudFront -> ALB 오리진 검증용 커스텀 헤더 시크릿 (비어있으면 헤더 자체를 안 붙임)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM Certificate ARN for CloudFront (only used in prod)"
  type        = string
  default     = ""
}

variable "waf_arn" {
  description = "WAF ARN to attach to CloudFront"
  type        = string
  default     = ""
}

variable "ops_logs_bucket_domain_name" {
  description = "S3 bucket domain name for CloudFront logs"
  type        = string
  default     = ""
}
