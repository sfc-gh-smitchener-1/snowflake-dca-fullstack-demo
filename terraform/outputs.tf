output "s3_bucket_name" {
  description = "S3 bucket name — use in upload_to_s3.py --bucket and in STORAGE_ALLOWED_LOCATIONS"
  value       = aws_s3_bucket.dca_raw.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.dca_raw.arn
}

output "s3_bucket_uri" {
  description = "S3 URI for the bucket root — use in CREATE EXTERNAL STAGE URL"
  value       = "s3://${aws_s3_bucket.dca_raw.id}/"
}

output "iam_role_arn" {
  description = "IAM role ARN — use in CREATE STORAGE INTEGRATION STORAGE_AWS_ROLE_ARN"
  value       = aws_iam_role.snowflake_s3_access.arn
}

output "iam_role_name" {
  description = "IAM role name"
  value       = aws_iam_role.snowflake_s3_access.name
}

output "aws_region" {
  description = "AWS region where the bucket was created"
  value       = var.aws_region
}

output "setup_instructions" {
  description = "Step-by-step instructions to complete the Snowflake storage integration"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════════╗
    ║  Next Steps — Snowflake Storage Integration Bootstrap           ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║                                                                  ║
    ║  1. Run sql/03b_s3_external_raw_layer.sql in Snowflake          ║
    ║     (use placeholder values for STORAGE_AWS_ROLE_ARN first)     ║
    ║                                                                  ║
    ║  2. In Snowflake, run:                                           ║
    ║     DESCRIBE INTEGRATION S3_RAW_INTEGRATION;                    ║
    ║     Copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID   ║
    ║                                                                  ║
    ║  3. Update terraform/variables.tf:                              ║
    ║     snowflake_aws_iam_user_arn = "<STORAGE_AWS_IAM_USER_ARN>"   ║
    ║     snowflake_external_id      = "<STORAGE_AWS_EXTERNAL_ID>"    ║
    ║                                                                  ║
    ║  4. Re-run: terraform apply                                      ║
    ║     (locks the IAM trust policy to Snowflake's principal)       ║
    ║                                                                  ║
    ║  5. Re-run sql/03b_s3_external_raw_layer.sql with real ARN      ║
    ║                                                                  ║
    ║  6. Upload data: python tools/upload_to_s3.py                   ║
    ║       --bucket ${aws_s3_bucket.dca_raw.id}                      ║
    ║       --data-dir data/                                           ║
    ║                                                                  ║
    ║  7. Refresh external tables in Snowflake:                       ║
    ║     ALTER EXTERNAL TABLE RAW_DEV.SAP.KNA1 REFRESH;              ║
    ║     (or use the REFRESH_ALL_EXTERNAL_TABLES procedure)          ║
    ╚══════════════════════════════════════════════════════════════════╝
  EOT
}
