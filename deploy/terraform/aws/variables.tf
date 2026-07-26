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

variable "primary_region" {
  type    = string
  default = "eu-central-1"
}

variable "dr_region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
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

variable "domain_name" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "waf_arn" {
  type = string
}

variable "workload_secret_arns" {
  type      = list(string)
  sensitive = true
  validation {
    condition     = length(var.workload_secret_arns) > 0
    error_message = "At least one approved secret ARN is required."
  }
}

variable "postgresql_engine_version" {
  type = string
  default = "18.4"
  validation { condition = can(regex("^18\\.", var.postgresql_engine_version)) error_message = "Use an approved PostgreSQL 18 engine version." }
}
