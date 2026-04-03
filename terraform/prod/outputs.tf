output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "route53_record" {
  description = "Application DNS record"
  value       = module.route53.route53_record_fqdn
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_instance_endpoint
}

output "app_irsa_role_arn" {
  description = "Application IRSA role ARN"
  value       = module.iam.app_role_arn
}

output "loki_irsa_role_arn" {
  description = "Loki IRSA role ARN"
  value       = module.loki_irsa.iam_role_arn
}

output "tempo_irsa_role_arn" {
  description = "Tempo IRSA role ARN"
  value       = module.tempo_irsa.iam_role_arn
}