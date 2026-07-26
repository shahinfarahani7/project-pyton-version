# Checkpoint and Resume

Checkpointing is permitted only at deterministic safe points. A checkpoint is encrypted, signed, bound to assignment ID, fence token, model digest, input digest, sequence, and device key. The server rejects stale fences, mismatched artifacts, replays, or checkpoints from another device. Local checkpoints are deleted after acknowledgement or retention expiry.
