# Task, Revision, Attempt and Assignment Semantics

- Task can have multiple revisions, but only one current draft/submitted pointer.
- Revision contains the canonical payload hash and exact policy references.
- Attempt belongs to exactly one revision and may have multiple sequential auto-assigned leases after machine failure or expiry.
- At most one live assignment lease exists for an attempt.
- The router atomically reserves capacity, creates the assignment in `leased`, allocates the fence token, updates the attempt, and writes outbox evidence. There is no offer or worker acceptance state.
- Current consent plus Worker `Available` status is the worker opt-in authority.
- The Worker Agent automatically starts a valid assignment and reports `started`; the user is not prompted.
- WebSocket ACK proves transport receipt only. It does not approve execution.
- If local conditions changed, the agent reports a closed machine-detected unavailability reason. The server may reassign with a higher fence token.
- A result with an older token is stored as rejected evidence and cannot trigger billing or reward.
- Retry after execution failure creates attempt number `max + 1` under a serializable or application-locked transaction.
- Consensus creates independent attempts with a common verification group, not multiple workers on one ordinary lease.
