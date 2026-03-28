output "app_role_arn" {
  value       = aws_iam_role.app_role.arn
  description = "Annotate your K8s ServiceAccount with this ARN"
}

output "app_policy_arn" {
  value = aws_iam_policy.app_policy.arn
}

output "jenkins_agent_role_arn" {
  value = module.jenkins_agent_irsa.iam_role_arn
}
# Output the IAM Role ARN for GitHub Actions (used in GitHub Secrets)
output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions OIDC authentication"
  value       = aws_iam_role.github_actions.arn
}

# Output the OIDC Provider ARN (useful for debugging / validation)
output "github_oidc_provider_arn" {
  description = "OIDC Provider ARN for GitHub"
  value       = aws_iam_openid_connect_provider.github.arn
}