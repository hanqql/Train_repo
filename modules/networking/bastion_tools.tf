# ==============================================================================
# Bastion 부트스트랩 도구용 S3 버킷
#
# eks_bastion user_data가 kubectl/helm을 dl.k8s.io / raw.githubusercontent.com에서
# curl로 받아오면 NAT Gateway가 필요했다. 이 버킷에서 받도록 바꿔서, 이미 모든 라우트
# 테이블에 연결돼 있는 S3 Gateway 엔드포인트(vpc_endpoints.tf)만으로 해결되게 했다.
#
# 주의: 바이너리를 이 버킷에 올리는 것 자체는 Terraform 범위 밖이다. 인터넷이 되는
# 환경에서 한 번 받아 아래 키로 업로드해둬야 한다 (버전 갱신 시에도 동일):
#   s3://<bucket>/tools/kubectl
#   s3://<bucket>/tools/helm
# ==============================================================================

resource "aws_s3_bucket" "bastion_tools" {
  bucket        = "${var.project_name}-${var.environment}-bastion-tools"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-bastion-tools"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "bastion_tools" {
  bucket = aws_s3_bucket.bastion_tools.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bastion_tools" {
  bucket = aws_s3_bucket.bastion_tools.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

# eks_bastion 역할만 tools/* 를 읽을 수 있다
resource "aws_iam_role_policy" "eks_bastion_tools_read" {
  name = "${var.project_name}-${var.environment}-eks-bastion-tools-read"
  role = aws_iam_role.eks_bastion_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.bastion_tools.arn}/tools/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.s3.arn
      }
    ]
  })
}
