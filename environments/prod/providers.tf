terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50, < 6.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}



provider "helm" {
  kubernetes {
    host                   = module.eks-cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks-cluster.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks-cluster.cluster_name]
    }
  }
}
