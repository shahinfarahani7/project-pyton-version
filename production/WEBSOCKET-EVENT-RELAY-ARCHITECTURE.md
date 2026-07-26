# Durable WebSocket Event Relay Architecture

## Decision

EdgeMint uses secure WebSocket as the only real-time event transport and Microsoft PostgreSQL as the only durable database. No external message broker or secondary database is part of the canonical architecture.

## Reliability model

WebSocket is a connection protocol, not durable storage. Reliability is therefore provided by PostgreSQL tables and stored procedures:

1. A domain transaction writes business state and a `dbo.outbox_events` row in the same PostgreSQL transaction.
2. Event Relay instances claim unpublished outbox rows with bounded leases and `UPDLOCK`, `READPAST`, and `ROWLOCK` semantics.
3. The relay expands each event into durable per-subscription delivery rows.
4. Connected consumers receive CloudEvents over `wss://<host>/events/v1`.
5. A consumer acknowledges only after its local transaction and inbox record commit.
6. Unacknowledged deliveries return to the queue after the acknowledgement deadline.
7. Reconnect uses a signed resume token and the durable last-acknowledged sequence.
8. Exhausted deliveries move to a durable dead-letter table and require an audited replay decision.

## Delivery guarantees

- At-least-once delivery.
- Idempotency through event ID and consumer inbox uniqueness.
- Per-aggregate ordering through a monotonic aggregate sequence.
- No global ordering guarantee.
- Maximum 256 unacknowledged deliveries per connection.
- Maximum frame size 1 MiB.
- Heartbeat every 20 seconds.
- Acknowledgement timeout 30 seconds.
- Event retention 30 days and dead-letter retention 90 days.

## Horizontal scale

Each connection has one SQL-backed owner lease. Load-balancer stickiness improves connection stability but is not a correctness dependency. If a relay pod fails, the lease expires, the client reconnects, and delivery resumes from PostgreSQL without losing acknowledged position.

## Security

- TLS 1.2 or newer; production endpoint is WSS only.
- The API Gateway validates external identity during the HTTP upgrade and delegates a one-time internal bearer token; the Event Relay validates that token before accepting the socket.
- The public API Gateway enforces an exact browser Origin allowlist and BFF session; the internal Event Relay rejects every Origin header.
- Workspace and permission claims bind every subscription.
- Subscription filters are server-authorized; clients cannot subscribe across workspace boundaries.
- Frames are strict-JSON validated against canonical identifier, field, event-catalog, size, rate, and authorization rules. Security-sensitive replay actions are append-only audited.
- Resume tokens are opaque 256-bit random values; only their SHA-256 hashes are stored, and they are short-lived, rotated, and bound to principal, workspace, and client identity.

## Backpressure

The relay stops claiming new deliveries when a connection reaches its in-flight limit. Slow consumers are disconnected after policy thresholds, while their durable delivery rows remain replayable. Database load is protected by bounded claim batches, exponential backoff with jitter, and circuit breakers.

## Failure behavior

The design is fail-closed. If PostgreSQL is unavailable, no event is reported as durably published. If a frame cannot be acknowledged, it is retried. If authorization context cannot be verified, the connection or subscription is rejected.

## Public edge and internal authentication

The API Gateway owns the public WebSocket route. It validates browser sessions or external bearer tokens and exchanges them for one-time, short-lived delegated tokens with audience `edgemint-event-relay`. PostgreSQL stores a hash of every consumed delegated token identifier, so replay is rejected even across relay replicas. The Event Relay is private, bearer-only, and never receives browser cookies or external provider tokens.

## Retention maintenance

A bounded PostgreSQL maintenance procedure removes acknowledged delivery history, expired dead letters, eligible outbox and inbox rows, and disconnected connection metadata according to the canonical 30-day event and 90-day dead-letter policies. Cleanup is incremental, transaction-bound, and cannot delete an outbox event while a delivery or dead-letter reference remains.
