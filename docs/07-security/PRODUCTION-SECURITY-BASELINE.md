# Production Security Baseline

- OIDC with PKCE for interactive applications; MFA required for operators.
- API keys are 256-bit random secrets, prefix-indexed, Argon2id-hashed with a server-side pepper in KMS-backed Secrets Manager.
- Service-to-service traffic uses mTLS and workload identity. No shared service passwords.
- Worker private keys never leave hardware-backed secure storage where available.
- Result and heartbeat signatures are mandatory.
- All customer data is encrypted in transit and at rest with per-environment KMS keys.
- Default-deny network policy, restricted egress, WAF, rate limiting, request-size limits, and SSRF-resistant webhook delivery are mandatory.
- Audit logs use a hash chain, object-lock archive, and restricted write-only service role.
- Dependency, container, IaC, secret, license, SAST, DAST, and mobile security scans run on every release.
- Critical vulnerabilities block release; high vulnerabilities require documented exception with expiry shorter than 14 days.
