# modules/rds/main.tf

# 1. DB Subnet Group - Defines which subnets the RDS can live in
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_data_subnet_ids

  tags = merge(var.common_tags, { Name = "${var.project_name}-db-subnet-group" })
}

# 2. RDS Instance - Production Grade MySQL
resource "aws_db_instance" "main" {
  identifier        = "${var.project_name}-db"
  engine            = "mysql"
  engine_version    = "8.0.33" # Matches your connector version
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"

  # Database Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password # Use Secrets Manager in real production!

  # Network & Security
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false
  multi_az               = var.environment == "prod" ? true : false

  # Encryption & Backups
  storage_encrypted               = true
  kms_key_id                      = var.kms_key_arn
  backup_retention_period         = 7
  backup_window                  = "03:00-04:00"
  maintenance_window             = "mon:04:00-mon:05:00"
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  # Protection
  deletion_protection      = var.environment == "prod" ? true : false
  skip_final_snapshot      = var.environment == "prod" ? false : true
  final_snapshot_identifier = "${var.project_name}-db-final-snapshot"

  tags = merge(var.common_tags, { Name = "${var.project_name}-rds" })
}