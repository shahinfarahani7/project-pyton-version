# Environment Configuration Matrix

| Setting | Local | Development | Staging | Production |
|---|---|---|---|---|
| token claim | disabled | disabled | simulated | compliance-gated |
| real payouts | no | no | sandbox | gated |
| model signature | test key | required | required | required + HSM/KMS |
| attestation | mock | optional paid tasks blocked | real | real/fail-closed |
| cloud fallback | local stub | sandbox | enabled | customer policy |
| RLS | enabled | enabled | enabled | enabled |
| PII logs | prohibited | prohibited | prohibited | prohibited |
| destructive reset | allowed | controlled | prohibited | prohibited |
