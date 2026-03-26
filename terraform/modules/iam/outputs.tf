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