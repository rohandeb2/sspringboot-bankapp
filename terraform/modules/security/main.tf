resource "aws_kms_key" "main" {
  description = "KMS key for ${var.project_name} resource encryption" 
  deletion_window_in_days = 30 
  enable_key_rotation     = true 

  tags = merge(var.common_tags, { Name = "${var.project_name}-kms" }) 
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-key" 
  target_key_id = aws_kms_key.main.key_id
}

resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg" 
  description = "Security group for all nodes in the cluster" 
  vpc_id      = var.vpc_id 

  ingress {
  from_port = 0
  to_port   = 0
  protocol  = "-1"
  self      = true
  description = "Allow all inbound traffic from within the security group (node-to-node communication)"
  }
  egress {
    from_port   = 0          
    to_port     = 0
    protocol    = "-1"       
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  security_groups = [var.alb_sg_id]
  description     = "Allow HTTP traffic from ALB to nodes (for app access)"
  }


  tags = merge(var.common_tags, { 
    Name                                           = "${var.project_name}-nodes-sg" 
    "kubernetes.io/cluster/${var.project_name}-eks" = "owned" 
    "karpenter.sh/discovery"                       = var.project_name 
  })
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg" 
  description = "Allow traffic from EKS nodes only" 
  vpc_id      = var.vpc_id 

  ingress {
    description     = "MySQL from EKS nodes" 
    from_port       = 3306 
    to_port         = 3306
    protocol        = "tcp" 
    security_groups = [aws_security_group.eks_nodes.id] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"       
    cidr_blocks = ["0.0.0.0/0"] 
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-rds-sg" }) 
}