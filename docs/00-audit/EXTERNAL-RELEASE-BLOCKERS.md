# Production Release Status

Unresolved design blockers: **0**

External release evidence requirements: **41**

External evidence is supplied by the target organization and release. It is exact, typed, owned, and fail-closed; it is not an implementation ambiguity.

| Category | Input | Owner | Validation |
|---|---|---|---|
| cloud | `AWS_ACCOUNT_ID` | Platform | `^[0-9]{12}$` |
| cloud | `AWS_PRIMARY_REGION` | Platform | `eu-central-1` |
| cloud | `AWS_DR_REGION` | Platform | `eu-west-1` |
| cloud | `ROUTE53_ZONE_ID` | Platform | `^Z[A-Z0-9]+$` |
| cloud | `PRODUCTION_DOMAIN` | Platform | `^[a-z0-9.-]+$` |
| cloud | `TERRAFORM_STATE_BUCKET` | Platform | `^[a-z0-9.-]+$` |
| cloud | `TERRAFORM_LOCK_TABLE` | Platform | `^[A-Za-z0-9_.-]+$` |
| cloud | `EKS_CLUSTER_VERSION` | Platform | `^1\.[0-9]+$` |
| cloud | `EKS_ADDON_VERSION_MANIFEST` | Platform | `^evidence/actual/platform/eks-addon-versions\.json$` |
| cloud | `PLATFORM_ADMIN_ROLE_ARN` | Security | `^arn:aws:iam::[0-9]{12}:role/` |
| cloud | `DATABASE_GENERATION` | Database | `^[A-Za-z0-9._-]+$` |
| cloud | `POSTGRES_ENGINE` | Database | `postgres` |
| cloud | `POSTGRES_ENGINE_VERSION` | Database | `18.4` |
| cloud | `POSTGRES_PARAMETER_GROUP_FAMILY` | Database | `postgres18` |
| identity | `COGNITO_CUSTOMER_POOL_ID` | Security | `^[a-z0-9-]+_[A-Za-z0-9]+$` |
| identity | `COGNITO_OPERATIONS_POOL_ID` | Security | `^[a-z0-9-]+_[A-Za-z0-9]+$` |
| identity | `PLAY_INTEGRITY_SERVICE_ACCOUNT_SECRET_ARN` | Mobile Security | `^arn:aws:secretsmanager:` |
| identity | `APPLE_APP_ATTEST_KEY_SECRET_ARN` | Mobile Security | `^arn:aws:secretsmanager:` |
| identity | `OPERATIONS_OIDC_PROVIDER_NAME` | Security | `^[A-Za-z0-9_-]{3,32}$` |
| identity | `OPERATIONS_OIDC_ISSUER` | Security | `^https://` |
| identity | `OPERATIONS_OIDC_CLIENT_ID_SECRET_ARN` | Security | `^arn:aws:secretsmanager:` |
| identity | `OPERATIONS_OIDC_CLIENT_SECRET_ARN` | Security | `^arn:aws:secretsmanager:` |
| identity | `OPERATOR_IDP_FIDO2_POLICY_EVIDENCE` | Security | `^evidence/actual/identity/operator-fido2-policy\.json$` |
| payments | `STRIPE_SECRET_KEY_ARN` | Finance | `^arn:aws:secretsmanager:` |
| payments | `STRIPE_WEBHOOK_SECRET_ARN` | Finance | `^arn:aws:secretsmanager:` |
| payments | `STRIPE_CONNECT_PLATFORM_ACCOUNT_ID` | Finance | `^acct_[A-Za-z0-9]+$` |
| supplyChain | `COSIGN_KMS_KEY_ARN` | Security | `^arn:aws:kms:` |
| supplyChain | `COSIGN_TRUSTED_PUBLIC_KEY_SHA256` | Security | `^[a-f0-9]{64}$` |
| supplyChain | `MODEL_SIGNING_KMS_KEY_ARN` | ML Platform | `^arn:aws:kms:` |
| supplyChain | `ISTIO_VERSION` | Platform | `^[0-9]+\.[0-9]+\.[0-9]+$` |
| supplyChain | `ISTIO_CHART_PROVENANCE_EVIDENCE` | Security | `^evidence/actual/platform/istio-provenance\.json$` |
| supplyChain | `MINIO_IMAGE` | Platform | `^[a-z0-9./:_-]+@sha256:[0-9a-f]{64}$` |
| supplyChain | `MAILPIT_IMAGE` | Platform | `^[a-z0-9./:_-]+@sha256:[0-9a-f]{64}$` |
| supplyChain | `PYTHON_RUNTIME_IMAGE` | Platform | `^[a-z0-9./:_-]+@sha256:[0-9a-f]{64}$` |
| supplyChain | `POSTGRES_DEV_IMAGE` | Database | `^[a-z0-9./:_-]+@sha256:[0-9a-f]{64}$` |
| supplyChain | `POSTGRES_TOOLS_IMAGE` | Database | `^[a-z0-9./:_-]+@sha256:[0-9a-f]{64}$` |
| models | `GA1_MODEL_RELEASE_MANIFEST` | ML Lead | `^evidence/actual/models/.+\.json$` |
| approvals | `RELEASE_APPROVAL_MANIFEST` | Release Manager | `^evidence/actual/legal-finance/signed-approvals\.json$` |
| approvals | `LEGAL_PRIVACY_APPROVAL` | Legal | `^evidence/actual/legal-finance/privacy-dpa\.json$` |
| approvals | `FINANCE_TAX_PAYOUT_APPROVAL` | Finance | `^evidence/actual/legal-finance/payout-tax-kyc\.json$` |
| approvals | `MODEL_LICENSE_APPROVAL` | Legal | `^evidence/actual/legal-finance/model-licenses\.json$` |
