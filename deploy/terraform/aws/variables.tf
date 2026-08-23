variable "aws_region" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "application_security_group_id" { type = string }
variable "postgresql_engine_version" {
  type    = string
  default = "18.4"
}
variable "database_instance_class" {
  type    = string
  default = "db.r7g.large"
}
variable "database_name" {
  type    = string
  default = "edgemint"
}
variable "database_username" {
  type      = string
  sensitive = true
}
variable "database_password" {
  type      = string
  sensitive = true
}
variable "database_kms_key_arn" { type = string }

