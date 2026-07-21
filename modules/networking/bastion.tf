# ==============================================================================
# DB Bastion Instance (SSM-only, Multi-AZ)
# AZ-a 장애 시 AZ-c Bastion으로 Aurora 긴급 접근 가능
# ==============================================================================
resource "aws_instance" "db_bastion" {
  ami                         = "ami-00e1a894b4512388e"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.db_bastion.id]
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.bastion_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y mariadb105
  EOF

  tags = {
    Name        = "${var.project_name}-db-bastion-a"
    Environment = var.environment
  }
}

resource "aws_instance" "db_bastion_c" {
  ami                         = "ami-00e1a894b4512388e"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_c.id
  vpc_security_group_ids      = [aws_security_group.db_bastion.id]
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.bastion_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y mariadb105
  EOF

  tags = {
    Name        = "${var.project_name}-db-bastion-c"
    Environment = var.environment
  }
}

# ==============================================================================
# EKS Bastion Instance (SSM-only, Multi-AZ, with kubectl & helm)
# AZ-a 장애 시 AZ-c Bastion으로 kubectl 긴급 대응 가능
# ==============================================================================
resource "aws_instance" "eks_bastion" {
  ami                         = "ami-00e1a894b4512388e"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.eks_bastion.id]
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.eks_bastion_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    # kubectl/helm: S3 Gateway 엔드포인트로 받아서 NAT Gateway가 필요 없다
    # (bastion_tools.tf 참고 - 바이너리는 사전에 s3://${aws_s3_bucket.bastion_tools.bucket}/tools/ 에 업로드돼 있어야 함)
    aws s3 cp s3://${aws_s3_bucket.bastion_tools.bucket}/tools/kubectl /usr/local/bin/kubectl
    chmod +x /usr/local/bin/kubectl
    aws s3 cp s3://${aws_s3_bucket.bastion_tools.bucket}/tools/helm /usr/local/bin/helm
    chmod +x /usr/local/bin/helm
  EOF

  tags = {
    Name        = "${var.project_name}-eks-bastion-a"
    Environment = var.environment
  }
}

resource "aws_instance" "eks_bastion_c" {
  ami                         = "ami-00e1a894b4512388e"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_c.id
  vpc_security_group_ids      = [aws_security_group.eks_bastion.id]
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.eks_bastion_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    # kubectl/helm: S3 Gateway 엔드포인트로 받아서 NAT Gateway가 필요 없다
    # (bastion_tools.tf 참고 - 바이너리는 사전에 s3://${aws_s3_bucket.bastion_tools.bucket}/tools/ 에 업로드돼 있어야 함)
    aws s3 cp s3://${aws_s3_bucket.bastion_tools.bucket}/tools/kubectl /usr/local/bin/kubectl
    chmod +x /usr/local/bin/kubectl
    aws s3 cp s3://${aws_s3_bucket.bastion_tools.bucket}/tools/helm /usr/local/bin/helm
    chmod +x /usr/local/bin/helm
  EOF

  tags = {
    Name        = "${var.project_name}-eks-bastion-c"
    Environment = var.environment
  }
}
