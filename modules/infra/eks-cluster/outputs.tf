output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks-cluster.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint for your EKS Kubernetes API server"
  value       = module.eks-cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "The base64 encoded certificate data required to communicate with your cluster"
  value       = module.eks-cluster.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider associated with the EKS cluster"
  value       = module.eks-cluster.oidc_provider_arn
}

output "oidc_provider" {
  description = "The OIDC Provider URL associated with the EKS cluster"
  value       = module.eks-cluster.oidc_provider
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID"
  value       = aws_lb.main.zone_id
}

output "app_tg_arn" {
  description = "App Target Group ARN for TargetGroupBinding"
  value       = aws_lb_target_group.app_tg.arn
}

# CloudWatch HealthyHostCount 알람 dimension용 (Route53 Failover 헬스체크에 사용)
output "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch dimensions"
  value       = aws_lb.main.arn_suffix
}

output "app_tg_arn_suffix" {
  description = "Target Group ARN suffix for CloudWatch dimensions"
  value       = aws_lb_target_group.app_tg.arn_suffix
}

output "cluster_autoscaler_policy_arn" {
  description = "IAM Policy ARN for Cluster Autoscaler"
  value       = aws_iam_policy.eks_cluster_autoscaler.arn
}