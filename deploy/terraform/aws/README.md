# AWS Production Infrastructure

This root provisions VPC, three availability zones, EKS, IRSA, KMS, immutable ECR repositories, encrypted/versioned S3, Amazon RDS for PostgreSQL 18 Multi-AZ, Cognito, WAF, CloudTrail, AWS Backup, budgets and cross-region backup copy.

The WebSocket Event Relay runs on EKS. Durable event state is stored only in PostgreSQL. No external event broker, secondary database or distributed cache is provisioned.
