# --- A. KARPENTER NODE ROLE (The role for the EC2s) ---
resource "aws_iam_role" "karpenter_node" {
  name = "${var.project_name}-karpenter-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach standard EKS Worker policies
resource "aws_iam_role_policy_attachment" "karpenter_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Essential for debugging
  ])
  policy_arn = each.value
  role       = aws_iam_role.karpenter_node.name
}

# Create the Instance Profile (This is what EC2 actually uses)
resource "aws_iam_instance_profile" "karpenter" {
  name = "${var.project_name}-karpenter-instance-profile"
  role = aws_iam_role.karpenter_node.name
}

# --- B. KARPENTER CONTROLLER ROLE (IRSA) ---
resource "aws_iam_policy" "karpenter_controller" {
  name = "${var.project_name}-karpenter-controller-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ec2:DescribeImages",
          "ec2:RunInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DeleteLaunchTemplate",
          "ec2:CreateRemoteAccessSession",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = "iam:PassRole"
        Effect   = "Allow"
        Resource = aws_iam_role.karpenter_node.arn
      },
      {
        Action   = "ec2:TerminateInstances"
        Effect   = "Allow"
        # 12 LPA LOGIC: Only allow Karpenter to terminate its own nodes
        Condition = { StringLike = { "ec2:ResourceTag/karpenter.sh/nodepool": "*" } }
        Resource = "*"
      }
    ]
  })
}

# The IRSA Role (OIDC)
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                          = "${var.project_name}-karpenter-controller-irsa"
  attach_karpenter_controller_policy = false

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter-sa"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.karpenter_controller.arn
  }
}