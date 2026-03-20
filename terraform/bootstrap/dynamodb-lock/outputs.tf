output "lock_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "The name of the DynamoDB table for state locking"
}

output "lock_table_arn" {
  value = aws_dynamodb_table.terraform_locks.arn
}