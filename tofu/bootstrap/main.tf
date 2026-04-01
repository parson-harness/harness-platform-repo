################################################################################
# Bootstrap Module - S3 Backend for Terraform State
# Run this ONCE per AWS account to create the state storage infrastructure
################################################################################

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
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "harness-demo"
      ManagedBy = "tofu-bootstrap"
      Owner     = var.owner
    }
  }
}

################################################################################
# Variables
################################################################################

variable "aws_region" {
  description = "AWS region for state bucket"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner name (SE last name or POV name)"
  type        = string
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name"
  type        = string
  default     = "harness-demo-tfstate"
}

################################################################################
# S3 Bucket for State
################################################################################

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.bucket_prefix}-${var.owner}-${random_id.bucket_suffix.hex}"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name  = "Terraform State Bucket"
    Owner = var.owner
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# DynamoDB Table for State Locking
################################################################################

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "harness-demo-tfstate-lock-${var.owner}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name  = "Terraform State Lock Table"
    Owner = var.owner
  }
}

################################################################################
# Outputs
################################################################################

output "state_bucket_name" {
  description = "S3 bucket name for terraform state"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for terraform state"
  value       = aws_s3_bucket.tfstate.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "backend_config" {
  description = "Backend configuration to add to your environment"
  value       = <<-EOT
    # Add this to your environment's main.tf:
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.tfstate.id}"
        key            = "harness-demo/<environment>/terraform.tfstate"
        region         = "${var.aws_region}"
        encrypt        = true
        dynamodb_table = "${aws_dynamodb_table.tfstate_lock.name}"
      }
    }
  EOT
}
