terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.35"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.1"
    }
  }
  required_version = ">= 1.2.0"
}


# This file is only for declaring providers and common resources.

provider "aws" {
  region                   = var.aws_region
  shared_credentials_files = ["${var.aws_cred_file}"]
  profile                  = "${var.aws_cred_profile}"
}
