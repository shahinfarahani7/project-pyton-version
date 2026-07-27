variable "project" {
  type    = string
  default = "edgemint"
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production"
  }
}

variable "aws_account_id" {
  type        = string
  description = "Bound to production/RELEASE-INPUTS.yaml AWS_ACCOUNT_ID."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account id."
  }
}

variable "primary_region" {
  type        = string
  default     = "eu-central-1"
  description = "Bound to production/RELEASE-INPUTS.yaml AWS_PRIMARY_REGION."
}

variable "dr_region" {
  type        = string
  default     = "eu-west-1"
  description = "Bound to production/RELEASE-INPUTS.yaml AWS_DR_REGION."
}

variable "hosted_zone_id" {
  type        = string
  description = "Bound to production/RELEASE-INPUTS.yaml ROUTE53_ZONE_ID."
  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.hosted_zone_id))
    error_message = "hosted_zone_id must be a Route53 hosted zone id."
  }
}

variable "domain_name" {
  type        = string
  description = "Bound to production/RELEASE-INPUTS.yaml PRODUCTION_DOMAIN."
  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.domain_name))
    error_message = "domain_name must be a lowercase DNS name."
  }
}

variable "terraform_state_bucket" {
  type        = string
  description = "Bound to production/RELEASE-INPUTS.yaml TERRAFORM_STATE_BUCKET."
}

variable "terraform_lock_table" {
  type        = string
  description = "Bound to production/RELEASE-INPUTS.yaml TERRAFORM_LOCK_TABLE."
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "admin_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the public EKS endpoint."
}

variable "alert_email" {
  type = string
}

variable "platform_admin_role_arn" {
  type = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/", var.platform_admin_role_arn))
    error_message = "platform_admin_role_arn must be an IAM role ARN."
  }
}

variable "eks_cluster_version" {
  type    = string
  default = "1.31"
}

variable "eks_addon_versions" {
  type = map(string)
}

variable "database_master_username" {
  type      = string
  default   = "edgemint_admin"
  sensitive = true
}

variable "database_generation" {
  type        = string
  default     = "v1"
  description = "Change only through an approved replacement plan."
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "workload_secret_arns" {
  type      = list(string)
  sensitive = true
  validation {
    condition     = length(var.workload_secret_arns) > 0
    error_message = "At least one approved secret ARN is required."
  }
}

variable "operations_oidc_provider_name" {
  type = string
}

variable "operations_oidc_client_id" {
  type      = string
  sensitive = true
}

variable "operations_oidc_client_secret_arn" {
  type = string
}

variable "operations_oidc_issuer" {
  type = string
  validation {
    condition     = can(regex("^https://", var.operations_oidc_issuer))
    error_message = "operations_oidc_issuer must be an HTTPS issuer URL."
  }
}

variable "postgresql_engine_version" {
  type    = string
  default = "18.4"
  validation {
    condition     = can(regex("^18\\.", var.postgresql_engine_version))
    error_message = "Use an approved PostgreSQL 18 engine version."
  }
}
