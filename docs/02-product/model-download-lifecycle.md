# Model Download Lifecycle

States: offered, queued, downloading, paused, verifying, installed, warming, ready, deprecated, quarantined, deleting.

A production manifest contains artifact URL template, byte size, SHA-256, signing key ID, signature, runtime ABI, minimum app/runtime versions, license notice and benchmark profile. Download is resumable by byte range. Installation is atomic: a model becomes ready only after hash and signature verification. Rollout can be stopped remotely; an already-running task continues only when its pinned artifact is not revoked for security.
