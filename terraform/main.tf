terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    Project     = var.project_tag
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "snowflake-dca-raw-layer"
  }
}

# ============================================================================
# S3 BUCKET — raw landing zone for all source-system files
# ============================================================================

resource "aws_s3_bucket" "dca_raw" {
  bucket = var.bucket_name

  tags = merge(local.common_tags, {
    Name = var.bucket_name
  })
}

resource "aws_s3_bucket_versioning" "dca_raw" {
  bucket = aws_s3_bucket.dca_raw.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dca_raw" {
  bucket = aws_s3_bucket.dca_raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "dca_raw" {
  bucket = aws_s3_bucket.dca_raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "dca_raw" {
  bucket = aws_s3_bucket.dca_raw.id

  # Demo data expires after 90 days; adjust for production use
  rule {
    id     = "expire-demo-data"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ============================================================================
# IAM ROLE — assumed by Snowflake storage integration
# ============================================================================

data "aws_iam_policy_document" "snowflake_assume_role" {
  statement {
    sid     = "SnowflakeAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      # Snowflake-managed IAM user populated via DESCRIBE INTEGRATION
      identifiers = [var.snowflake_aws_iam_user_arn]
    }

    # ExternalId prevents confused-deputy attacks
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.snowflake_external_id]
    }
  }
}

resource "aws_iam_role" "snowflake_s3_access" {
  name               = "snowflake-dca-raw-s3-${var.environment}"
  description        = "Role assumed by Snowflake storage integration to read the DCA raw S3 bucket"
  assume_role_policy = data.aws_iam_policy_document.snowflake_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "snowflake_s3_policy" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.dca_raw.arn]
  }

  statement {
    sid    = "ReadObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = ["${aws_s3_bucket.dca_raw.arn}/*"]
  }
}

resource "aws_iam_role_policy" "snowflake_s3_access" {
  name   = "snowflake-dca-raw-s3-read"
  role   = aws_iam_role.snowflake_s3_access.id
  policy = data.aws_iam_policy_document.snowflake_s3_policy.json
}

# ============================================================================
# S3 BUCKET POLICY — enforce access only via the Snowflake IAM role
# (optional; tighten further for production)
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "dca_raw_bucket_policy" {
  statement {
    sid    = "DenyNonSnowflakeAccess"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.dca_raw.arn,
      "${aws_s3_bucket.dca_raw.arn}/*",
    ]
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values = [
        aws_iam_role.snowflake_s3_access.arn,
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "dca_raw" {
  bucket = aws_s3_bucket.dca_raw.id
  policy = data.aws_iam_policy_document.dca_raw_bucket_policy.json

  # Bucket policy must wait for public access block to be fully applied
  depends_on = [aws_s3_bucket_public_access_block.dca_raw]
}
