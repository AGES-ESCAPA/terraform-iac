terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Descomente para usar backend remoto (recomendado em time / múltiplas máquinas).
  # Sem isso, o state fica local em terraform.tfstate — funciona, mas não é seguro
  # em produção (sem locking, sem versionamento, fácil de perder o arquivo).
  #
  # backend "s3" {
  #   bucket         = "SEU_BUCKET_DE_STATE"
  #   key            = "escapa/k3s-single-node/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
  # Credenciais via env vars (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY) ou
  # ~/.aws/credentials (aws configure). Nunca hardcode aqui.
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
