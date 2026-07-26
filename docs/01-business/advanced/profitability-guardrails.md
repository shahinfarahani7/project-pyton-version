# Profitability Guardrails

Per quote, the platform computes expected variable cost from worker reward, verifier reward, cloud probability, storage, egress, payment fees, fraud reserve and support allocation.

Hard controls:
- customer price must cover expected variable cost plus minimum contribution margin.
- promotion subsidy must have an active budget reservation.
- passive reward spend is capped by both absolute budget and a percentage of recognized net revenue.
- worker reward cannot exceed configured share of net task revenue without an approved supply campaign.
- cloud fallback has daily and tenant-level cost caps.
- negative-margin routes are disabled automatically when the economy kill switch is active.
