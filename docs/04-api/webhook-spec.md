# Webhook Contract

- body is a CloudEvents 1.0 JSON event.
- headers: `X-EdgeMint-Event-Id`, `X-EdgeMint-Timestamp`, `X-EdgeMint-Signature-v1`.
- signature input is `<timestamp>.<rawBody>` using HMAC-SHA256.
- receiver accepts timestamps within five minutes and deduplicates by event ID.
- 2xx acknowledges; 408, 409, 425, 429 and 5xx retry; other 4xx are terminal.
- exponential backoff uses policy-defined delays and jitter, with a maximum attempt and dead-letter state.
- secret rotation supports current and previous secret overlap.
- replay creates a new delivery ID but preserves the domain event ID.
