# This code sets up Karpenter in your Amazon EKS cluster so that it can 
# automatically create and delete EC2 machines (nodes) based on workload

resource "aws_iam_role" "karpenter_node" { # Creates IAM role for EC2 nodes created by Karpenter
  name = "${var.project_name}-karpenter-node-role" # Name of the IAM role
  assume_role_policy = jsonencode({ # Defines who can assume this role
    Version = "2012-10-17" # Standard IAM policy version
    Statement = [{ # Start of permission rule
      Action = "sts:AssumeRole" # Allows the role to be assumed
      Effect = "Allow" # Grants permission
      Principal = { Service = "ec2.amazonaws.com" } # Only EC2 instances (nodes) can assume this role
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_policies" { # Attaches required permissions to node role
  for_each = toset([ # Loop through multiple policies
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy", # Allows node to talk to EKS control plane
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy", # Allows networking (IP assignment, ENI management)
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", # Allows pulling images from ECR
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Allows SSM access for debugging (no SSH needed)
  ])
  policy_arn = each.value # Attach each policy from list
  role = aws_iam_role.karpenter_node.name # Attach policies to the node IAM role
}

# Creates an instance profile (this is what EC2 actually uses to get IAM role permissions)Instance profile = a way to give an IAM role to EC2
resource "aws_iam_instance_profile" "karpenter" { 
  name = "${var.project_name}-karpenter-instance-profile" # Name of the instance profile
  role = aws_iam_role.karpenter_node.name # Attaches the Karpenter node IAM role to this profile
}

# --- B. KARPENTER CONTROLLER ROLE (IRSA) ---
resource "aws_iam_policy" "karpenter_controller" { # Creates IAM policy for Karpenter controller (brain)
  name = "${var.project_name}-karpenter-controller-policy" # Name of the policy
  
  policy = jsonencode({ # Define permissions in JSON format
    Version = "2012-10-17" # Standard IAM policy version

    Statement = [ # Start of permission rules

      {
        Action = [ # List of actions Karpenter is allowed to perform
          "ssm:GetParameter", # Read parameters (like AMI IDs from SSM)
          "ec2:DescribeImages", # View available AMIs
          "ec2:RunInstances", # Launch new EC2 instances (create nodes)
          "ec2:DescribeSubnets", # Get subnet info
          "ec2:DescribeSecurityGroups", # Get security group info
          "ec2:DescribeLaunchTemplates", # View launch templates
          "ec2:DescribeInstances", # View EC2 instances
          "ec2:DescribeInstanceTypes", # View instance types (t3, m5, etc.)
          "ec2:DescribeInstanceTypeOfferings", # Check which instance types are available
          "ec2:DescribeAvailabilityZones", # Get AZ info
          "ec2:DeleteLaunchTemplate", # Delete launch templates
          "ec2:CreateRemoteAccessSession", # Used for remote access (internal AWS ops)
          "ec2:CreateLaunchTemplate", # Create launch templates
          "ec2:CreateFleet", # Launch multiple instances (used by Karpenter)
          "ec2:DescribeSpotPriceHistory", # Get spot pricing info
          "pricing:GetProducts" # Get pricing details
        ]
        Effect   = "Allow" # Allow all above actions
        Resource = "*" # Applies to all resources
      },

      {
        Action   = "iam:PassRole" # Allows passing IAM role to EC2 instances
        Effect   = "Allow" # Grants permission
        Resource = aws_iam_role.karpenter_node.arn # Only allow passing the node IAM role
      },

      {
        Action   = "ec2:TerminateInstances" # Allows terminating EC2 instances
        Effect   = "Allow" # Grants permission

        Condition = { StringLike = { "ec2:ResourceTag/karpenter.sh/nodepool": "*" } } 
        #It can only terminate: EC2 instances-->That have tag → karpenter.sh/nodepool
        # Only allow terminating instances created by Karpenter (safety control)

        Resource = "*" # Applies to all EC2 instances (filtered by condition)
      }
    ]
  })
}

# This block gives Karpenter (running inside Kubernetes) permission to access AWS without using access keys.
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  #This module is downloaded from the Terraform Registry during terraform init and cached locally for reuse
  version = "~> 5.0"

  role_name                          = "bankapp-karpenter-controller-irsa"
  attach_karpenter_controller_policy = false ## We are NOT using default policy, we will attach our own custom policy

  oidc_providers = {    ## Defines OIDC trust (connects EKS with AWS IAM)
    main = {
      provider_arn = aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["karpenter:karpenter-sa"] ## Only this K8s service account can assume this role (Namespace → karpenter Service Account → karpenter-sa)
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.karpenter_controller.arn  ## Attaches custom Karpenter controller policy to this role
  }
}