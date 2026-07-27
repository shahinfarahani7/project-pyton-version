output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "database_endpoint" {
  value     = aws_db_instance.postgresql.address
  sensitive = true
}

output "database_port" {
  value = aws_db_instance.postgresql.port
}

output "database_secret_arn" {
  value     = aws_db_instance.postgresql.master_user_secret[0].secret_arn
  sensitive = true
}

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.id
}

output "certificate_arn" {
  value = aws_acm_certificate.main.arn
}

output "waf_arn" {
  value = aws_wafv2_web_acl.main.arn
}

output "workload_role_arns" {
  value = { for name, role in aws_iam_role.workload : name => role.arn }
}
