terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.7.2"
    }
  }

  backend "s3" {
    bucket         = "placeholder-set-at-init"
    key            = "edgemint/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "placeholder-set-at-init"
    encrypt        = true
  }
}

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = local.tags
  }
}
