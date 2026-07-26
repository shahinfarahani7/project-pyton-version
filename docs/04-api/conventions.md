# API Conventions

- Base path `/v1`; additive compatible changes only.
- JSON UTF-8, camelCase, RFC3339 UTC timestamps.
- opaque prefixed IDs.
- `X-Request-Id` accepted/generated; `traceparent` propagated.
- mutating commands require `Idempotency-Key` unless explicitly exempt.
- optimistic updates require `If-Match` and return ETag.
- list responses use cursor pagination.
- errors use the standard `Problem` schema with stable `code`.
- monetary micros are decimal strings in JSON.
- API keys use `X-EdgeMint-Key`; OAuth uses `Authorization: Bearer`.
