# don't forget to get the role arn from the tf prod output and add it as a secret in GitHub repo (e.g. GITHUB_OIDC_ROLE_ARN) 
# and then use that secret in your GitHub Actions workflow to assume the role for OIDC authentication.

# 1. Fetch GitHub's OIDC Certificate Thumbprint dynamically
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# 2. Create the OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# 3. Create the IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = "github-actions-oidc-role"

  # Trust Policy: Only allows YOUR repo to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:rohandeb2/sspringboot-bankapp:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# 4. Attach PowerUser or Admin permissions (Adjust based on Least Privilege)
resource "aws_iam_role_policy_attachment" "admin_access" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}