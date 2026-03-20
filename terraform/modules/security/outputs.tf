output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "eks_nodes_sg_id" {
  value = aws_security_group.eks_nodes.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}