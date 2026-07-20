# azure-prod가 먼저 apply 된 경우 MySQL FQDN을 자동으로 읽어옴.
# 첫 번째 apply(azure-prod state 없음)는 try()가 ""를 반환 → DMS 생성 건너뜀.
# azure-prod apply 완료 후 두 번째 prod apply 시 DMS가 자동 생성됨.
data "terraform_remote_state" "azure_prod" {
  backend = "local"
  config = {
    path = "../azure-prod/terraform.tfstate"
  }
}

# Secrets Manager에서 민감값 읽어옴 (비밀번호/토큰을 코드/tfvars에 평문으로 두지 않기 위함)
# apply 전 콘솔 또는 CLI로 "team-train-prod-secrets" Secret을 먼저 생성해야 함
data "aws_secretsmanager_secret_version" "prod" {
  secret_id = "${var.project_name}-prod-secrets"
}

locals {
  secrets = jsondecode(data.aws_secretsmanager_secret_version.prod.secret_string)
}

# Azure 리소스(VNet, VPN Gateway, LNG, Connection)는 environments/azure-prod 에서 전담 관리.
# AWS 측 VPN Connection은 Azure Gateway가 콘솔에서 페어링된 뒤 활성화됨.
# environments/azure-prod 의 terraform_remote_state 가 vpn_tunnel1/2 outputs 를 읽어 Azure LNG 를 구성함.
module "networking" {
  source           = "../../modules/networking"
  project_name     = var.project_name
  environment      = var.environment
  eks_cluster_name = "${var.project_name}-${var.environment}-eks"

  azure_vnet_cidr = var.azure_vnet_cidr
  # azure-prod apply 후 얻어지는 VPN Gateway IP 자동 할당
  azure_vpn_gateway_ip = try(data.terraform_remote_state.azure_prod.outputs.vpn_gateway_public_ip, "")

  security_alert_email = var.security_alert_email

  providers = {
    aws.us_east_1 = aws.us_east_1
  }
}

module "logging" {
  source       = "../../modules/infra/logging"
  project_name = var.project_name
  environment  = var.environment

  log_retention_days     = 30
  cloudtrail_bucket_name = module.networking.cloudtrail_s3_bucket

  # Fluent Bit IRSA 연동 (EKS Pod → CloudWatch Logs 전송)
  cluster_name      = module.eks-cluster.cluster_name
  oidc_provider_arn = module.eks-cluster.oidc_provider_arn
  oidc_provider     = module.eks-cluster.oidc_provider
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
  eks_bastion_sg_id       = module.networking.eks_bastion_sg_id

  eks_admin_principal_arns = var.eks_admin_principal_arns
  origin_verify_secret     = random_password.origin_verify_secret.result
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
  db_admin_password = local.secrets["db_admin_password"]
  redis_auth_token  = local.secrets["redis_auth_token"]
  # azure-prod state에서 자동으로 읽어옴. state가 없으면 ""(DMS 생성 건너뜀)
  azure_db_endpoint = try(data.terraform_remote_state.azure_prod.outputs.mysql_server_fqdn, "")
  azure_db_user     = var.azure_db_user
  azure_db_password = local.secrets["azure_db_password"]
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
  depends_on               = [module.database]

  # 기존 Route53 혹은 VPC 모듈에서 나오는 호스트존 ID output 값을 연결
  route53_zone_id = data.aws_route53_zone.primary.zone_id
}

# ==============================================================================
# Kustomize 환경변수(.env) 자동 생성 (ArgoCD/GitOps 연동용)
# ==============================================================================
resource "local_file" "backend_kustomize_env" {
  filename = "../../modules/infra/k8s-manifests/overlays/${var.environment}/backend-config.env"
  content  = <<-EOT
    # 이 파일은 Terraform에 의해 자동 생성되었습니다. 직접 수정하지 마세요.
    PORT=8080
    ALLOWED_ORIGINS=https://${var.project_name}.cloud,https://www.${var.project_name}.cloud
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
  origin_verify_secret                    = random_password.origin_verify_secret.result

  providers = {
    aws.us_east_1 = aws.us_east_1
  }
}

# CloudFront -> ALB 오리진 검증용 시크릿 헤더 값 (매 apply마다 안 바뀌게 고정, 수동 rotate 원하면 taint)
resource "random_password" "origin_verify_secret" {
  length  = 32
  special = false
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

# ==============================================================================
# Route53 DNS 서비스 레코드
# ==============================================================================
data "aws_route53_zone" "primary" {
  name         = "team-train.cloud"
  private_zone = false
}

# 1. 루트 도메인 (team-train.cloud) -> CloudFront Alias
resource "aws_route53_record" "main" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "team-train.cloud"
  type    = "A"

  alias {
    name                   = module.cdn.cloudfront_domain_name
    zone_id                = module.cdn.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# 2. www 서브도메인 (www.team-train.cloud) -> CloudFront Alias
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "www.team-train.cloud"
  type    = "A"

  alias {
    name                   = module.cdn.cloudfront_domain_name
    zone_id                = module.cdn.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# 3. API 서브도메인 (api.team-train.cloud) -> Route53 Failover
# PRIMARY: ALB, SECONDARY: Azure App Service
#
# ALB SG가 CloudFront prefix list로만 열려있어서, Route53 헬스체커 IP가 ALB에
# 직접 HTTP 프로브를 못 날림 (SG에서 차단됨) -> 그래서 HTTP 방식 헬스체크 대신
# ALB Target Group의 HealthyHostCount를 CloudWatch 알람으로 보고, Route53은 그
# "알람 상태"만 조회하는 CLOUDWATCH_METRIC 타입 헬스체크를 사용 (네트워크 트래픽 없이
# AWS 제어 영역 API로만 상태를 가져오므로 SG 룰과 무관하게 동작함)
resource "aws_cloudwatch_metric_alarm" "alb_healthy_hosts" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-healthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "ALB 타겟그룹에 healthy한 타겟이 없음 - Route53 Failover가 Azure App Service로 전환됨"
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = module.eks-cluster.alb_arn_suffix
    TargetGroup  = module.eks-cluster.app_tg_arn_suffix
  }

  tags = {
    Name        = "${var.project_name}-alb-healthy-hosts"
    Environment = var.environment
  }
}

resource "aws_route53_health_check" "api_primary" {
  type                            = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.alb_healthy_hosts.alarm_name
  cloudwatch_alarm_region         = var.aws_region
  insufficient_data_health_status = "Unhealthy"

  tags = {
    Name        = "${var.project_name}-api-primary-healthcheck"
    Environment = var.environment
  }
}

resource "aws_route53_record" "api_primary" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "api.team-train.cloud"
  # Secondary(CNAME)와 Failover 그룹으로 묶이려면 Type이 같아야 하므로 alias(A) 대신 CNAME 사용
  type           = "CNAME"
  ttl            = 60
  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.api_primary.id
  records         = [module.eks-cluster.alb_dns_name]
}

# Azure App Service 준비 전(빈 값)에는 Secondary 레코드 자체를 생성하지 않음
resource "aws_route53_record" "api_secondary" {
  count          = var.azure_app_service_hostname != "" ? 1 : 0
  zone_id        = data.aws_route53_zone.primary.zone_id
  name           = "api.team-train.cloud"
  type           = "CNAME"
  ttl            = 60
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  records = [var.azure_app_service_hostname]
}


# 4. DB 서브도메인 (db.team-train.cloud) -> Aurora MySQL Endpoint CNAME
resource "aws_route53_record" "db" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "db.team-train.cloud"
  type    = "CNAME"
  ttl     = 60
  records = [module.database.aurora_writer_endpoint]
}

# ==============================================================================
# Slack Alerting Module
# ==============================================================================
module "slack-alerting" {
  source = "../../modules/infra/slack-alerting"

  project_name      = var.project_name
  environment       = var.environment
  aws_region        = var.aws_region
  slack_webhook_url = local.secrets["slack_webhook_url"]
}
