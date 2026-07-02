variable "aws_region" {
  description = "AWS region for the S3 bucket"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev, stg, prod)"
  type        = string
  default     = "dev"
}

variable "bucket_name" {
  description = "S3 bucket name for the DCA raw layer. Must be globally unique."
  type        = string
  # Override at apply time: terraform apply -var='bucket_name=dca-raw-demo-123456789'
}

variable "project_tag" {
  description = "Project tag applied to all AWS resources"
  type        = string
  default     = "snowflake-dca-demo"
}

# ---------------------------------------------------------------------------
# Snowflake storage integration trust values
# Populate these AFTER running:
#   CREATE STORAGE INTEGRATION S3_RAW_INTEGRATION ...
#   DESCRIBE INTEGRATION S3_RAW_INTEGRATION;
# Then copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID here
# and run `terraform apply` again to lock the trust policy.
# ---------------------------------------------------------------------------

variable "snowflake_aws_iam_user_arn" {
  description = <<-EOT
    Snowflake-managed IAM user ARN from DESCRIBE INTEGRATION S3_RAW_INTEGRATION.
    Column: STORAGE_AWS_IAM_USER_ARN.
    Example: arn:aws:iam::123456789012:user/snowflake-xyz
  EOT
  type    = string
  default = "PENDING"
}

variable "snowflake_external_id" {
  description = <<-EOT
    External ID from DESCRIBE INTEGRATION S3_RAW_INTEGRATION.
    Column: STORAGE_AWS_EXTERNAL_ID.
    Example: ABC123_SFCRole=2_abc123=
  EOT
  type    = string
  default = "PENDING"
}
