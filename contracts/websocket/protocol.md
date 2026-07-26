# EdgeMint WebSocket Protocol v1

Endpoint: `wss://<environment-host>/events/v1`

Subprotocol: `edgemint.events.v1`

Every frame is UTF-8 JSON and must match `contracts/websocket/frame.schema.json`. The first client frame is `hello`; the server replies with `welcome` or `error`. A client then sends `subscribe` frames. Server `event` frames contain a CloudEvents 1.0 object. The client sends `ack` only after its processing transaction and inbox record commit. `ping` and `pong` are application heartbeats in addition to protocol-level control frames.

Resume tokens are opaque, signed, short-lived values. They are not database IDs and must not be decoded by clients. A resume request is rejected if principal, workspace, audience, or expiration does not match.

Browser clients authenticate to the public API Gateway with the secure BFF session cookie. Native and service clients authenticate to the gateway with external bearer tokens. The gateway validates the external identity, issues a one-time short-lived delegated bearer token for audience `edgemint-event-relay`, and opens the internal relay WebSocket. The Event Relay rejects browser Origin headers and consumes each delegated token identifier once. Credentials are never placed in the WebSocket URL or application frames.
