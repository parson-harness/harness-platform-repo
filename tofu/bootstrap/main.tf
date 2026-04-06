################################################################################
# Bootstrap Module - S3 Backend for Terraform State
# Run this ONCE per AWS account to create the state storage infrastructure
################################################################################

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

resource "aws_s3_bucket" "coverage_artifacts" {
  bucket = "${var.coverage_bucket_prefix}-${var.owner}-${random_id.bucket_suffix.hex}"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name  = "Coverage Artifact Bucket"
    Owner = var.owner
  }
}

resource "aws_s3_bucket_versioning" "coverage_artifacts" {
  bucket = aws_s3_bucket.coverage_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "coverage_artifacts" {
  bucket = aws_s3_bucket.coverage_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "coverage_artifacts" {
  bucket = aws_s3_bucket.coverage_artifacts.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "coverage_artifacts_public_read" {
  bucket = aws_s3_bucket.coverage_artifacts.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicReadCoverageArtifacts"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = ["${aws_s3_bucket.coverage_artifacts.arn}/*"]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.coverage_artifacts]
}

resource "aws_s3_bucket_lifecycle_configuration" "coverage_artifacts" {
  bucket = aws_s3_bucket.coverage_artifacts.id

  rule {
    id     = "expire-coverage-artifacts"
    status = "Enabled"

    filter {
      prefix = var.coverage_report_artifact_path_prefix
    }

    expiration {
      days = var.coverage_artifact_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.coverage_artifact_retention_days
    }
  }
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
