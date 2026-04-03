# modules/eks/main.tf

#IIt creates an IAM role that EKS assumes to get permissions to manage AWS resources for the cluster
resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({ #Defines who can assume (use) this role, converted to JSON.
    Version = "2012-10-17"
    Statement = [{  #Starts permission rules.
      Action = "sts:AssumeRole"   #Allows assuming the role.
      Effect = "Allow"    #Grants permission.
      Principal = { Service = "eks.amazonaws.com" }   #Only EKS service can assume this role
    }]
  }) 
}

#It attaches the AmazonEKSClusterPolicy to the IAM role, giving the EKS cluster permissions to manage AWS resources
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" { #Creates a resource to attach a policy to a role
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" #Uses AWS managed policy for **Amazon EKS cluster permissions
  role       = aws_iam_role.cluster.name   #Attaches this policy to your cluster IAM role
}

# In the first block, I create an IAM role and allow EKS to assume it. 
# In the second block, I attach a policy to that role to define what permissions it has

# 2. EKS Cluster Definition
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_app_subnet_ids
    endpoint_private_access = true 
    endpoint_public_access  = true # Set to false for production to restrict API access to VPC only
  }

  access_config {
    authentication_mode= "API_AND_CONFIG_MAP" 
    #We add this to enable both API-based and ConfigMap-based authentication in EKS for flexibility and backward compatibility
    #API → like login managed by Google (easy & secure)
    # ConfigMap → like manual guest list on paper
    bootstrap_cluster_creator_admin_permissions = true
    #It gives initial admin access
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
  #Ensures IAM role + permissions are ready before creating cluster
}

# 3. OIDC Provider for IRSA (IAM Roles for Service Accounts)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer #Fetches the SSL certificate from the EKS OIDC URL.Used to verify trust (security)
}

#This block lets the Amazon EKS pods talk to AWS services securely without using access keys by using OIDC provider
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"] 
  #Allows AWS STS (token service) to be used

  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint] 
  #Uses certificate fingerprint to verify identity securely

  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  #Links it to your EKS cluster’s OIDC URL
}

#This creates an IAM role for the worker nodes (EC2 machines) in your Amazon EKS cluster.
resource "aws_iam_role" "node_group" { 
  name = "${var.project_name}-eks-node-role"
  assume_role_policy = jsonencode({
  # Defines who can assume (use) this role, converted into JSON format
    Version = "2012-10-17"
    # Standard AWS IAM policy version
    Statement = [{ # Start of permission rule
      Action = "sts:AssumeRole"
      # Allows the role to be assumed (used)=
      Effect = "Allow"# Grants permission
      Principal = { Service = "ec2.amazonaws.com" }
      # Only EC2 instances can assume this role (EKS worker nodes run on EC2)

    }]
  })
}


resource "aws_iam_role_policy_attachment" "node_policies" {
  # Attaches multiple IAM policies to the node group role
  for_each = toset([
    # Loop over a set of policy ARNs (so we can attach multiple policies)
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    # Allows nodes to communicate with the EKS control plane
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    # Allows networking (CNI plugin) → assign IPs, manage network interfaces
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    # Allows nodes to pull Docker images from ECR
  ])
  policy_arn = each.value
  # Attaches each policy from the list one by one
  role = aws_iam_role.node_group.name
  # Attaches these policies to the node group IAM role
}

#This block creates the worker machines (servers) for your Amazon EKS cluster.
resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "general-purpose"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_app_subnet_ids

  capacity_type  = "SPOT" # Use "SPOT" for cost savings, or "ON_DEMAND" for guaranteed availability
  instance_types = ["m7i-flex.large"]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 4
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }
}
