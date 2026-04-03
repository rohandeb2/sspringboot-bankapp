  # modules/rds/main.tf

  data "aws_secretsmanager_secret" "banking-prod-db-secret" {
    name = "banking-prod-db-secret" # fetches the secret metadata using its name from Secrets Manager
  }

  # Get latest secret value
  data "aws_secretsmanager_secret_version" "db_secret_version" {
    secret_id = data.aws_secretsmanager_secret.banking-prod-db-secret.id # uses the secret ID to fetch the latest version of the secret value
  }

  locals {
    db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_secret_version.secret_string) # converts JSON string into a map (username/password usable)
  }
  # DB Subnet Group - defines private subnets where RDS will be deployed
  resource "aws_db_subnet_group" "main" {
    name       = "${var.project_name}-db-subnet-group"
    subnet_ids = var.private_data_subnet_ids

    tags = merge(var.common_tags, { Name = "${var.project_name}-db-subnet-group" }) # tagging for tracking
  }

  # RDS MySQL instance (production-grade configuration)
  resource "aws_db_instance" "main" {
    identifier     = "${var.project_name}-db" #It sets the unique name of your RDS database instance in AWS
    engine         = "mysql"              # database engine
    engine_version = "8.4.7"       # compatible MySQL version

    instance_class = var.db_instance_class # compute + memory size

    allocated_storage = 20                # storage in GB
    storage_type      = "gp3"             # improved SSD storage

    db_name  = var.db_name
    username = local.db_creds.db_username
    password = local.db_creds.db_password

    db_subnet_group_name   = aws_db_subnet_group.main.name # private subnet placement
    vpc_security_group_ids = [var.rds_sg_id]               # controls access
    publicly_accessible    = false                         # disables public access

    multi_az = var.environment == "prod" ? true : false    # HA only in production

    storage_encrypted = true              # encrypt data at rest
    kms_key_id        = var.kms_key_arn   # custom encryption key

    # backup_retention_period = 7           # retain backups for 7 days
    backup_window           = "03:00-04:00" # backup schedule

    maintenance_window = "mon:04:00-mon:05:00" # maintenance timing

    enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"] # logs to CloudWatch

    # deletion_protection = var.environment == "dev" ? true  : false # prevent accidental delete in prod

    skip_final_snapshot = var.environment == "prod" ? false : true # ensure snapshot in prod

    final_snapshot_identifier = "${var.project_name}-db-final-snapshot" # final backup name

    tags = merge(var.common_tags, { Name = "${var.project_name}-rds" }) # resource tagging
  }