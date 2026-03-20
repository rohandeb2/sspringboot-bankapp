output "db_instance_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "db_instance_id" {
  value = aws_db_instance.main.identifier
}

output "db_instance_port" {
  value = aws_db_instance.main.port
}