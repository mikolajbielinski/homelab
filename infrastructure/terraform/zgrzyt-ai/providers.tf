terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "zgrzyt-ai-tfstate"
    key          = "zgrzyt-ai/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}
