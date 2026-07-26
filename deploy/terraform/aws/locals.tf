data "aws_availability_zones" "available" { state = "available" }
data "aws_caller_identity" "current" {}
locals {
  name          = "edgemint-${var.environment}"
  azs           = slice(data.aws_availability_zones.available.names, 0, 3)
  service_names = [
    "api-gateway",
    "identity",
    "customer",
    "file",
    "task-intake",
    "pricing",
    "router",
    "worker-gateway",
    "worker-registry",
    "result",
    "verification",
    "billing",
    "ledger",
    "reward",
    "claim",
    "fraud",
    "webhook",
    "model-registry",
    "notification",
    "operations", "event-relay"
  ]
  tags = { Product = "EdgeMint", Environment = var.environment, ManagedBy = "Terraform", DataClassification = "confidential" }
}
