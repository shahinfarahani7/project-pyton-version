resource "aws_cognito_user_pool" "customer" {
  name                = "${local.name}-customer"
  deletion_protection = var.environment == "production" ? "ACTIVE" : "INACTIVE"
  mfa_configuration   = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length    = 14
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "customer" {
  name                                 = "${local.name}-customer-web"
  user_pool_id                         = aws_cognito_user_pool.customer.id
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = ["https://${var.domain_name}/auth/callback"]
  logout_urls                          = ["https://${var.domain_name}/logout"]
}

resource "aws_cognito_user_pool" "operations" {
  name                = "${local.name}-operations"
  deletion_protection = var.environment == "production" ? "ACTIVE" : "INACTIVE"
  mfa_configuration   = "OFF"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length    = 32
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
}

data "aws_secretsmanager_secret_version" "operations_oidc_client_secret" {
  secret_id = var.operations_oidc_client_secret_arn
}

resource "aws_cognito_identity_provider" "operations_oidc" {
  user_pool_id  = aws_cognito_user_pool.operations.id
  provider_name = var.operations_oidc_provider_name
  provider_type = "OIDC"

  provider_details = {
    authorize_scopes          = "openid email profile"
    client_id                 = var.operations_oidc_client_id
    client_secret             = data.aws_secretsmanager_secret_version.operations_oidc_client_secret.secret_string
    attributes_request_method = "GET"
    oidc_issuer               = var.operations_oidc_issuer
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}

resource "aws_cognito_user_pool_client" "operations" {
  name                                 = "${local.name}-operations-web"
  user_pool_id                         = aws_cognito_user_pool.operations.id
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  supported_identity_providers         = [aws_cognito_identity_provider.operations_oidc.provider_name]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = ["https://${var.domain_name}/operations/auth/callback"]
  logout_urls                          = ["https://${var.domain_name}/operations/logout"]
}

resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate : record.fqdn]
}

resource "aws_wafv2_web_acl" "main" {
  name  = local.name
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.name
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWSManagedCommon"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }
}
