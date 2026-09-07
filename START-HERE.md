# Start Here

1. Read [docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md](docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md) (canonical architecture; supersedes v1).
2. Read `production/canonical-decisions.yaml`.
3. Read `production/AUTO-ASSIGNMENT-PROTOCOL.md`.
4. Read `production/WEBSOCKET-EVENT-RELAY-ARCHITECTURE.md`.
5. Read `database/README.md`.
6. Read `cursor/CURSOR-EXECUTION-ORDER.md` for the exact dependency-aware Cursor implementation sequence.
7. Read `cursor/VERIFICATION-PROMPTS.md` for baseline, per-package, auto-assignment, and final verification prompts.
8. Run `bash tools/validate_all.sh` (or individual `tools/validate_*.py` scripts on Windows).
9. Give Cursor `cursor/CURSOR-MASTER-PROMPT.md` and execute Work Packages using the selection rule in `cursor/work-packages.json`.
10. Run the matching independent verification prompt after every Work Package.
11. Never mark a deployment production certified until `python tools/production_gate.py` passes against real, signed environment evidence.

The pack resolves design and implementation ambiguity. It does not fabricate cloud credentials, legal approvals, security test results, signed images, database restore results, or live deployment evidence.
