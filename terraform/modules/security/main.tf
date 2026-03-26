# modules/security/main.tf

# KMS Key for encrypting data across AWS services (RDS, S3, EBS)
resource "aws_kms_key" "main" {
  description             = "KMS key for ${var.project_name} resource encryption" # key purpose
  deletion_window_in_days = 30 # grace period before deletion
  enable_key_rotation     = true # automatic key rotation (security best practice)

  tags = merge(var.common_tags, { Name = "${var.project_name}-kms" }) # tagging for tracking
}

# Alias for easier reference of KMS key
resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-key" # friendly name for key
  target_key_id = aws_kms_key.main.key_id         # link to actual KMS key
}

# Security group for EKS worker nodes (controls outbound traffic)
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg" # SG name
  description = "Security group for all nodes in the cluster" # purpose
  vpc_id      = var.vpc_id # attach to VPC

  ingress {
  from_port = 0
  to_port   = 0
  protocol  = "-1"
  self      = true
  description = "Allow all inbound traffic from within the security group (node-to-node communication)"
  }
  egress {
    from_port   = 0          # allow all outbound traffic
    to_port     = 0
    protocol    = "-1"       # all protocols
    cidr_blocks = ["0.0.0.0/0"] # open egress (default for nodes)
  }

  ingress {
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  security_groups = [alb_sg_id]
  description     = "Allow HTTP traffic from ALB to nodes (for app access)"
  }


  tags = merge(var.common_tags, { 
    Name                                           = "${var.project_name}-nodes-sg" # SG name tag
    "kubernetes.io/cluster/${var.project_name}-eks" = "owned" # EKS cluster ownership
    "karpenter.sh/discovery"                       = var.project_name # used by Karpenter autoscaling
  })
}

# Security group for RDS (restricts access to only EKS nodes)
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg" # SG name
  description = "Allow traffic from EKS nodes only" # security description
  vpc_id      = var.vpc_id # attach to VPC

  ingress {
    description     = "MySQL from EKS nodes" # access rule description
    from_port       = 3306 # MySQL port
    to_port         = 3306
    protocol        = "tcp" # TCP protocol
    security_groups = [aws_security_group.eks_nodes.id] # allow only from EKS nodes (source-based restriction)
  }

  egress {
    from_port   = 0          # allow outbound traffic
    to_port     = 0
    protocol    = "-1"       # all protocols
    cidr_blocks = ["0.0.0.0/0"] # open egress
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-rds-sg" }) # tagging
}