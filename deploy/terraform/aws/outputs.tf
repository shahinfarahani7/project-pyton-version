output "postgresql_endpoint" {
  value     = aws_db_instance.postgresql.address
  sensitive = true
}

output "postgresql_port" { value = aws_db_instance.postgresql.port }

