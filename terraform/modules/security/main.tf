# modules/security/main.tf

# 1. KMS Key for Data Encryption (RDS/S3/EBS)
resource "aws_kms_key" "main" {
  description             = "KMS key for ${var.project_name} resource encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true # Compliance Best Practice

  tags = merge(var.common_tags, { Name = "${var.project_name}-kms" })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-key"
  target_key_id = aws_kms_key.main.key_id
}

# 2. Security Group for EKS Worker Nodes
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Security group for all nodes in the cluster"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { 
    Name                                           = "${var.project_name}-nodes-sg"
    "kubernetes.io/cluster/${var.project_name}-eks" = "owned"
    "karpenter.sh/discovery" = var.project_name
  })
}

# 3. Security Group for RDS MySQL
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow traffic from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from EKS nodes"
    from_port       = 3306 # Matches application.properties
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id] # Source-based locking
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-rds-sg" })
}