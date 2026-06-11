# rds module

data "aws_secretsmanager_secret" "banking_prod_db_secret" {
  name = "banking-prod-db-secret"
}

data "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id = data.aws_secretsmanager_secret.banking_prod_db_secret.id
}

locals {
  db_creds = jsondecode(
    data.aws_secretsmanager_secret_version.db_secret_version.secret_string
  )
}


resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_data_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}


resource "aws_db_instance" "main" {

  identifier = "${var.project_name}-db"

  engine         = "mysql"
  engine_version = "8.0"

  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = local.db_creds.db_username
  password = local.db_creds.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]

  publicly_accessible = false

  multi_az = var.environment == "prod" ? true : false

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  backup_window = "03:00-04:00"

  maintenance_window = "mon:04:00-mon:05:00"

  enabled_cloudwatch_logs_exports = [
    "error",
    "general",
    "slowquery"
  ]

  skip_final_snapshot = var.environment == "prod" ? false : true

  final_snapshot_identifier = "${var.project_name}-db-final-snapshot"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rds"
  })
}