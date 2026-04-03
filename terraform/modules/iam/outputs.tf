output "app_role_arn" {
  description = "IAM role ARN for application (IRSA)"
  value       = aws_iam_role.app_role.arn
}

output "app_policy_arn" {
  description = "IAM policy ARN for application"
  value       = aws_iam_policy.app_policy.arn
}

output "jenkins_irsa_role_arn" {
  description = "IAM role ARN for Jenkins agent IRSA"
  value       = module.jenkins_agent_irsa.iam_role_arn
}

output "velero_irsa_role_arn" {
  description = "IAM role ARN for Velero IRSA"
  value       = module.velero_irsa.iam_role_arn
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = aws_iam_role.github_actions.arn
}