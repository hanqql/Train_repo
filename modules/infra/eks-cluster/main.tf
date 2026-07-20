# ==============================================================================
# 1. AWS 계정 정보 및 데이터 참조
# ==============================================================================
data "aws_caller_identity" "current" {}

# 필요 시 주석 풀고 사용
# data "aws_vpc" "selected" {
#   tags = {
#     Name = "${var.project_name}-vpc"
#   }
# }

# ==============================================================================
# 2. AWS EKS 클러스터 빌드
# ==============================================================================
module "eks-cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-${var.environment}-eks"
  cluster_version = "1.30"

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # IAM Identity에 관리자 권한 부여
  enable_cluster_creator_admin_permissions = true

  # 클러스터 컨트롤 플레인 로깅 활성화
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Access Entry 설정
  # 계정 root ARN 통짜 부여(모든 IAM 주체에게 admin) 대신, eks_admin_principal_arns로 지정한
  # 특정 IAM Role/User에게만 admin 권한 부여 (enable_cluster_creator_admin_permissions가
  # terraform apply 실행자 본인에게는 이미 admin을 부여하므로 이 목록은 나머지 팀원용)
  access_entries = merge(
    {
      for idx, arn in var.eks_admin_principal_arns : "admin_${idx}" => {
        kubernetes_groups = []
        principal_arn     = arn

        policy_associations = {
          admin_policy = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    },
    var.enable_bastion_access ? {
      bastion_access = {
        kubernetes_groups = []
        principal_arn     = var.eks_bastion_role_arn

        policy_associations = {
          admin_policy = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    } : {}
  )

  # Bastion 보안 그룹에서의 API Server (443) 접근 허용
  cluster_security_group_additional_rules = var.enable_bastion_access ? {
    ingress_bastion = {
      description              = "Allow Bastion to access EKS API"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      type                     = "ingress"
      source_security_group_id = var.eks_bastion_sg_id
    }
  } : {}

  # HPA + Cluster Autoscaler(CA) 요구사항 반영
  eks_managed_node_groups = {
    fixed_node_group = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 8
      desired_size   = 3
      disk_size      = 50 # 기본값 20GB에서 50GB로 증가 (저장소 부족 방지)

      vpc_security_group_ids = [var.eks_sg_id]

      # 노드 역할 정책
      iam_role_additional_policies = {
        AmazonEKSClusterAutoscalerPolicy    = aws_iam_policy.eks_cluster_autoscaler.arn
        AmazonEC2ContainerRegistryPowerUser = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
        AmazonEKS_CNI_Policy                = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        CloudWatchAgentServerPolicy         = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"                                    = "true"
        "k8s.io/cluster-autoscaler/${var.project_name}-${var.environment}-eks" = "owned"
      }
    }
  }

  # 추후 ALB까지 배포 할 수 있도록
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.developer_ips
  cluster_endpoint_private_access      = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-cluster"
    Environment = var.environment
  }
}

# ==============================================================================
# 3. IAM 정책 생성 (Cluster Autoscaler 연동용)
# ==============================================================================
resource "aws_iam_policy" "eks_cluster_autoscaler" {
  name        = "${var.project_name}-${var.environment}-eks-ca-policy"
  description = "IAM policy for EKS Cluster Autoscaler inside Node Group"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeLaunchTemplateVersions",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeSubnets",
          "ec2:DescribeAvailabilityZones",
          "ec2:GetInstanceTypesFromInstanceRequirements"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# 4. ALB to Node Security Group Rule
# ==============================================================================
resource "aws_security_group_rule" "alb_to_node" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = module.eks-cluster.node_security_group_id
  source_security_group_id = var.alb_sg_id
  description              = "Allow ALB to access Node on 8080"
}