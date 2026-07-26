# Privacy Data Map

| Data | Purpose | Location | Retention owner |
|---|---|---|---|
| account identity/contact | authentication/support | identity service | account policy |
| device capability/attestation | worker eligibility/security | worker registry | security policy |
| task payload | inference | object storage + temporary worker | task DataPolicy |
| result | customer service/audit | result storage | task DataPolicy |
| telemetry | reliability/fraud | observability/fraud stores | telemetry policy |
| payment/invoice | billing/legal | billing provider/database | finance/legal |
| KYC/claim | payout/compliance | provider + minimal reference | compliance policy |

Sensitive payload content is excluded from logs, analytics and support by default. Support access requires explicit case-based elevation.
