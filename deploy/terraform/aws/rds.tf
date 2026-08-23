terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" { region = var.aws_region }

resource "aws_db_subnet_group" "edgemint" {
  name       = "edgemint-${var.environment}"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "postgresql" {
  name_prefix = "edgemint-${var.environment}-postgresql-"
  description = "PostgreSQL access from EdgeMint application services only"
  vpc_id      = var.vpc_id

  ingress {
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [var.application_security_group_id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_db_instance" "postgresql" {
  identifier = "edgemint-${var.environment}"

  engine         = "postgres"
  engine_version = var.postgresql_engine_version
  instance_class = var.database_instance_class
  port           = 5432
  db_name        = var.database_name
  username       = var.database_username
  password       = var.database_password

  allocated_storage     = 100
  max_allocated_storage = 1000
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.database_kms_key_arn

  multi_az                           = true
  publicly_accessible                = false
  iam_database_authentication_enabled = true
  db_subnet_group_name               = aws_db_subnet_group.edgemint.name
  vpc_security_group_ids             = [aws_security_group.postgresql.id]

  backup_retention_period = 35
  backup_window           = "01:00-02:00"
  maintenance_window      = "sun:03:00-sun:04:00"
  deletion_protection     = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "edgemint-${var.environment}-final"

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.database_kms_key_arn
  performance_insights_retention_period = 7
  enabled_cloudwatch_logs_exports        = ["postgresql", "upgrade"]
  auto_minor_version_upgrade             = true
  apply_immediately                      = false
  copy_tags_to_snapshot                  = true

  tags = {
    Service     = "edgemint"
    Environment = var.environment
    DataClass   = "confidential"
  }
}

