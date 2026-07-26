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
