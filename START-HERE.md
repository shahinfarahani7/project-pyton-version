# Start Here

1. Read `production/canonical-decisions.yaml`.
2. Read `production/AUTO-ASSIGNMENT-PROTOCOL.md`.
3. Read `production/WEBSOCKET-EVENT-RELAY-ARCHITECTURE.md`.
4. Read `database/README.md`.
5. Read `cursor/CURSOR-EXECUTION-ORDER.md` for the exact dependency-aware Cursor implementation sequence.
6. Read `cursor/VERIFICATION-PROMPTS.md` for baseline, per-package, auto-assignment, and final verification prompts.
7. Run `bash tools/validate_all.sh`.
8. Give Cursor `cursor/CURSOR-MASTER-PROMPT.md` and execute Work Packages using the selection rule in `cursor/work-packages.json`.
9. Run the matching independent verification prompt after every Work Package.
10. Never mark a deployment production certified until `python tools/production_gate.py` passes against real, signed environment evidence.

The pack resolves design and implementation ambiguity. It does not fabricate cloud credentials, legal approvals, security test results, signed images, database restore results, or live deployment evidence.
