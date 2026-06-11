resource "aws_iam_role" "karpenter_node" {
  name = "${var.project_name}-karpenter-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ])

  policy_arn = each.value
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "${var.project_name}-karpenter-profile"
  role = aws_iam_role.karpenter_node.name
}

resource "aws_iam_policy" "karpenter_controller" {

  name = "${var.project_name}-karpenter-controller-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      {
        Action = [
          "ec2:RunInstances",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeAvailabilityZones",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts",
          "ssm:GetParameter"
        ]
        Effect   = "Allow"
        Resource = "*"
      },

      {
        Action = "iam:PassRole"
        Effect = "Allow"
        Resource = aws_iam_role.karpenter_node.arn
      },

      {
        Action = "ec2:TerminateInstances"
        Effect = "Allow"
        Resource = "*"

        Condition = {
          StringLike = {
            "ec2:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      }
    ]
  })
}


module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "karpenter-controller-irsa"

  attach_karpenter_controller_policy = false

  oidc_providers = {
    main = {
      provider_arn = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = [
        "karpenter:karpenter-sa"
      ]
    }
  }

  role_policy_arns = {
    custom = aws_iam_policy.karpenter_controller.arn
  }
}