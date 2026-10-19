terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  # Uncomment and configure this block if you want to store state remotely in S3:
  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "invoice-processor/terraform.tfstate"
  #   region         = "ap-southeast-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "invoice-processor"
      ManagedBy = "terraform"
    }
  }
}

provider "random" {}