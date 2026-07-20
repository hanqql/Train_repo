module "networking" {
  source           = "../../modules/networking"
  project_name     = var.project_name
  environment      = var.environment
  eks_cluster_name = "${var.project_name}-${var.environment}-eks"

  security_alert_email = var.security_alert_email

  providers = {
    aws.us_east_1 = aws.us_east_1
  }
}

module "logging" {
  source       = "../../modules/infra/logging"
  project_name = var.project_name
  environment  = var.environment

  log_retention_days = 7
}

module "eks-cluster" {
  source        = "../../modules/infra/eks-cluster"
  project_name  = var.project_name
  environment   = var.environment
  developer_ips = var.developer_ips

  vpc_id                  = module.networking.vpc_id
  subnet_ids              = module.networking.private_subnet_ids
  public_subnet_ids       = module.networking.public_subnet_ids
  alb_sg_id               = module.networking.alb_sg_id
  eks_sg_id               = module.networking.eks_sg_id
  acm_alb_certificate_arn = module.networking.acm_alb_certificate_arn
  ops_logs_bucket_id      = module.logging.ops_logs_bucket_id
  eks_bastion_role_arn    = module.networking.eks_bastion_role_arn

  eks_admin_principal_arns = var.eks_admin_principal_arns
}

module "cognito" {
  source       = "../../modules/infra/cognito"
  project_name = var.project_name
  environment  = var.environment
}



module "database" {
  source       = "../../modules/database"
  project_name = var.project_name
  environment  = var.environment

  db_subnet_group_name    = module.networking.db_subnet_group_name
  redis_subnet_group_name = module.networking.redis_subnet_group_name
  dms_subnet_group_name   = module.networking.dms_replication_subnet_group_id
  dms_sg_id               = module.networking.dms_sg_id
  aurora_sg_id            = module.networking.aurora_sg_id
  redis_sg_id             = module.networking.redis_sg_id

  db_admin_user     = var.db_admin_user
  db_admin_password = var.db_admin_password
  azure_db_endpoint = var.azure_db_endpoint
  azure_db_user     = var.azure_db_user
  azure_db_password = var.azure_db_password

  redis_auth_token = var.redis_auth_token
}

module "frontend-pipeline" {
  source       = "../../modules/infra/frontend-pipeline"
  project_name = var.project_name
  environment  = var.environment

  frontend_bucket_name       = module.networking.s3_frontend_bucket
  cloudfront_distribution_id = module.cdn.cloudfront_distribution_id

  github_repo = "hjin-2e/Front_Train"

  create_github_oidc_provider = true
}

module "backend-pipeline" {
  source       = "../../modules/infra/backend-pipeline"
  project_name = var.project_name
  environment  = var.environment

  github_repo = "Chjjh605/Backend_Train"
}

data "aws_route53_zone" "primary" {
  name         = "team-train.cloud"
  private_zone = false
}

# 내부 통신 알림
module "notification" {
  source                   = "../../modules/infra/notification"
  project_name             = var.project_name
  environment              = var.environment
  aws_region               = var.aws_region
  sqs_queue_arn            = module.database.mail_queue_arn
  sqs_queue_name           = module.database.sqs_queue_name
  notification_email       = var.notification_email
  verified_email_or_domain = var.verified_email_or_domain
  route53_zone_id          = data.aws_route53_zone.primary.zone_id
  depends_on               = [module.database]
}

# ==============================================================================
# Kustomize 환경변수(.env) 자동 생성 (ArgoCD/GitOps 연동용)
# ==============================================================================
resource "local_file" "backend_kustomize_env" {
  filename = "../../modules/infra/k8s-manifests/overlays/${var.environment}/backend-config.env"
  content  = <<-EOT
    # 이 파일은 Terraform에 의해 자동 생성되었습니다. 직접 수정하지 마세요.
    PORT=8080
    ALLOWED_ORIGINS=https://${module.cdn.cloudfront_domain_name}
    AWS_REGION=${var.aws_region}
    
    # SQS 및 DB
    SQS_QUEUE_URL=${module.database.sqs_queue_url}
    MAIL_QUEUE_URL=${module.database.mail_queue_url}
    DB_HOST=${module.database.aurora_writer_endpoint}
    DB_PORT=3306
    DB_NAME=trail_db
    
    REDIS_HOST=${module.database.redis_primary_endpoint}
    REDIS_PORT=6379
    REDIS_AUTH_TOKEN=${var.redis_auth_token}
    
    # Cognito
    COGNITO_USER_POOL_ID=${module.cognito.user_pool_id}
    COGNITO_CLIENT_ID=${module.cognito.user_pool_client_id}
    USE_MOCK_AUTH=false
  EOT
}

# ==============================================================================
# TargetGroupBinding 패치 자동 생성 (ArgoCD 연동용)
# ==============================================================================
resource "local_file" "targetgroupbinding_patch" {
  filename = "../../modules/infra/k8s-manifests/overlays/${var.environment}/targetgroupbinding-patch.yaml"
  content  = <<-EOT
# 이 파일은 Terraform에 의해 자동 생성되었습니다. 직접 수정하지 마세요.
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: backend-targetgroup-binding
  namespace: default
spec:
  targetType: ip
  targetGroupARN: ${module.eks-cluster.app_tg_arn}
  EOT
}

module "cdn" {
  source = "../../modules/infra/cdn"

  project_name                            = var.project_name
  environment                             = var.environment
  s3_frontend_bucket_id                   = module.networking.s3_frontend_bucket
  s3_frontend_bucket_arn                  = module.networking.s3_frontend_bucket_arn
  s3_frontend_bucket_regional_domain_name = module.networking.s3_frontend_bucket_regional_domain_name
  alb_dns_name                            = module.eks-cluster.alb_dns_name
  waf_arn                                 = module.networking.waf_arn
  acm_certificate_arn                     = module.networking.acm_certificate_arn
  ops_logs_bucket_domain_name             = module.logging.ops_logs_bucket_domain_name

  providers = {
    aws.us_east_1 = aws.us_east_1
  }
}

moved {
  from = module.networking.aws_cloudfront_distribution.main
  to   = module.cdn.aws_cloudfront_distribution.main
}

moved {
  from = module.networking.aws_cloudfront_origin_access_control.main
  to   = module.cdn.aws_cloudfront_origin_access_control.main
}

moved {
  from = module.networking.aws_s3_bucket_policy.frontend
  to   = module.cdn.aws_s3_bucket_policy.frontend
}
