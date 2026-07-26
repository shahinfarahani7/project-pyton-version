# Minty Animation State Map

| Domain state | Animation | Allowed copy |
|---|---|---|
| unavailable | sleeping/maintenance | Worker paused; no new assignments |
| ready | slow crystal sorting | Available for automatic missions |
| leased/start pending | alert light then equipment check | Mission assigned; starting automatically |
| downloading model | equipment delivery | Preparing model |
| running OCR | scanning glyph crystals | Processing document locally |
| running audio | echo cave | Transcribing audio locally |
| uploading | cart delivery | Sending encrypted result |
| verifying | lab inspection | Result under verification |
| verified | reward vault | Verified reward added |
| failure worker-neutral | tool repair | Mission reassigned; no penalty |
| policy/security failure | guarded pause | Worker review required |

Animation must be driven by server/native state. It must not fabricate task progress or reward. No state may display per-task Accept or Reject controls.
