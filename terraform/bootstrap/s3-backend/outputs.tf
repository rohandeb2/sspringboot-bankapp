output "state_bucket_id" {
  value       = aws_s3_bucket.state_bucket.id
  description = "Bucket ID for Terraform Backend"
}

output "state_bucket_arn" {
  value = aws_s3_bucket.state_bucket.arn
}