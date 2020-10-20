terraform {
  required_version = ">= 0.13"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  backend "s3" {
    key    = "terraform.tfstate"
    region = "ca-central-1"
  }
}