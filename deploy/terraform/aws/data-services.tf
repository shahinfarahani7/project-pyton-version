resource "aws_security_group" "postgresql" {
  name = "${local.name}-postgresql"
  vpc_id = aws_vpc.main.id
  ingress { from_port=5432 to_port=5432 protocol="tcp" security_groups=[aws_eks_cluster.main.vpc_config[0].cluster_security_group_id] }
  egress { from_port=0 to_port=0 protocol="-1" cidr_blocks=["0.0.0.0/0"] }
}
resource "aws_db_subnet_group" "main" { name=local.name subnet_ids=aws_subnet.private[*].id }
resource "random_id" "database_generation" { byte_length=4 keepers={ generation=var.database_generation } }
resource "aws_db_parameter_group" "postgresql" {
  name="${local.name}-postgresql-18" family="postgres18"
  parameter { name="rds.force_ssl" value="1" apply_method="immediate" }
  parameter { name="log_min_duration_statement" value="500" apply_method="immediate" }
  parameter { name="idle_in_transaction_session_timeout" value="60000" apply_method="immediate" }
}
resource "aws_db_instance" "postgresql" {
  identifier="${local.name}-postgresql"
  engine="postgres" engine_version=var.postgresql_engine_version
  instance_class=var.environment=="production" ? "db.r7g.2xlarge" : "db.r7g.xlarge"
  allocated_storage=500 max_allocated_storage=4000 storage_type="gp3" storage_encrypted=true kms_key_id=aws_kms_key.platform.arn
  multi_az=true db_name="edgemint" username=var.database_master_username manage_master_user_password=true
  db_subnet_group_name=aws_db_subnet_group.main.name parameter_group_name=aws_db_parameter_group.postgresql.name
  vpc_security_group_ids=[aws_security_group.postgresql.id] port=5432
  backup_retention_period=35 backup_window="02:00-03:00" maintenance_window="sun:04:00-sun:05:00"
  deletion_protection=var.deletion_protection skip_final_snapshot=false final_snapshot_identifier="${local.name}-final-${random_id.database_generation.hex}"
  performance_insights_enabled=true performance_insights_kms_key_id=aws_kms_key.platform.arn
  auto_minor_version_upgrade=false apply_immediately=false enabled_cloudwatch_logs_exports=["postgresql","upgrade"]
  copy_tags_to_snapshot=true publicly_accessible=false iam_database_authentication_enabled=true
  lifecycle { prevent_destroy=true }
}
