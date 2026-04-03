output "s3_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state"
  value       = aws_s3_bucket.state_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 state bucket"
  value       = aws_s3_bucket.state_bucket.arn
}

output "s3_bucket_region" {
  description = "Region where the S3 bucket is created"
  value       = var.region
}