# Browser Session and WebSocket Authentication Contract

## Boundary

The public API Gateway is the Browser Backend-for-Frontend (BFF) and the public WebSocket edge. The Event Relay is an internal service and accepts only short-lived, audience-restricted bearer tokens issued for server-to-server delegation. Browser cookies are never shared with the Event Relay.

## Browser session

- The API Gateway completes OIDC Authorization Code with PKCE and stores provider tokens only in server-side encrypted storage.
- The browser receives only the `__Host-edgemint-session` opaque cookie: Secure, HttpOnly, host-only, path `/`, SameSite `Strict`, and no Domain attribute.
- The cookie contains a random token. PostgreSQL stores only its SHA-256 hash and the session record.
- The server rotates the session after sign-in, reauthentication, privilege change, workspace switch, and risk escalation.
- Absolute expiration, idle expiration, authorization generation, revocation, and risk state are checked on every privileged HTTP request and WebSocket upgrade.
- Logout revokes the PostgreSQL session before clearing the browser cookie.

## Browser WebSocket path

1. The browser opens `wss://<public-host>/events/v1` with subprotocol `edgemint.events.v1`.
2. The API Gateway validates TLS, exact Origin, the BFF session, workspace binding, authorization generation, rate limit, and subprotocol.
3. The API Gateway creates a short-lived delegated JWT containing principal, workspace, permissions, audience `edgemint-event-relay`, session identifier, authorization generation, and a unique token identifier.
4. The API Gateway opens the internal relay WebSocket with that bearer token and proxies validated protocol frames with bounded buffers and cancellation in both directions.
5. Session revocation, workspace change, authorization-generation change, or risk lock closes both public and internal sockets within the revocation SLO.

Native Worker and service clients may connect through the API Gateway with bearer authentication. The gateway validates the external token and delegates a new internal token; it never forwards an untrusted external token directly to the relay.

## Event Relay requirements

- Bearer authentication only; any HTTP `Origin` header is rejected because browsers must terminate at the API Gateway.
- Internal audience, issuer, lifetime, token identifier, principal, workspace, authorization generation, and permissions are mandatory.
- Credentials are forbidden in the URL and WebSocket application frames.
- The relay derives principal, workspace, and permissions only from the validated delegated token.

## Required tests

Tests must cover login CSRF, session fixation, cookie theft mitigation, Origin rejection, cross-workspace subscription, revoked session, stale authorization generation, logout, workspace switching, delegated-token replay, token leakage, slow-client backpressure, reconnect, and relay failover. Production release is blocked unless these tests and evidence pass.
