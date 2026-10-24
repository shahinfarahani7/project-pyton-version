from pathlib import Path

path = Path("/app/src/backend/edgemint/workers/enrollment.py")
text = path.read_text(encoding="utf-8")
old = 'raise worker_error("HEARTBEAT_SEQUENCE_INVALID", detail="replay or stale sequence")'
new = 'raise worker_error("HEARTBEAT_SEQUENCE_INVALID", detail=f"replay or stale sequence; lastSequence={last_sequence}")'
if old not in text:
    raise SystemExit("expected heartbeat stale line not found")
text = text.replace(old, new)
gap = (
    '        if payload.sequence != last_sequence + 1:\n'
    '            raise worker_error("HEARTBEAT_SEQUENCE_INVALID", detail="sequence gap")\n\n'
)
text = text.replace(gap, "")
path.write_text(text, encoding="utf-8")
print("enrollment heartbeat patched")
