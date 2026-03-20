output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  value = module.rds.db_instance_endpoint
}

output "app_iam_role_arn" {
  value       = module.iam.app_role_arn
  description = "Use this to annotate the K8s ServiceAccount for the banking app."
}