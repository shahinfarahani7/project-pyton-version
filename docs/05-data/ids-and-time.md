# IDs, Time and Canonicalization

Canonical JSON uses UTF-8, lexicographically sorted object keys, no insignificant whitespace and normalized decimal strings. Payload hash is SHA-256 of canonical bytes. Client timestamps are informational; server time controls expiry and ordering. UUIDv7 improves index locality but public APIs expose opaque prefixed identifiers.
