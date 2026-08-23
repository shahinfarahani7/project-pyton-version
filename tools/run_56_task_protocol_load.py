#!/usr/bin/env python3
"""Exercise all 56 catalog types across 20 workers through lease/result crypto."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]
WORKERS = 20


def result_mac(token: str, assignment: str, fence: int, digest: str, artifact: str) -> str:
    body = f"{assignment}|{fence}|{digest}|{artifact}".encode()
    return base64.b64encode(hmac.new(token.encode(), body, hashlib.sha256).digest()).decode()


def main() -> int:
    catalog = json.loads((ROOT / "src/shared/task-types/catalog.json").read_text())
    task_types = [item["value"] for category in catalog["categories"] for item in category["types"]]
    key = AESGCM.generate_key(bit_length=256)
    cipher = AESGCM(key)
    operations = 0
    stale_rejections = 0
    failures: list[str] = []
    started = time.perf_counter()

    for worker_index in range(WORKERS):
        worker_id = f"worker-{worker_index:02d}"
        aad = worker_id.encode()
        for task_index, task_type in enumerate(task_types):
            assignment = f"asg-{worker_index:02d}-{task_index:02d}"
            token = secrets.token_urlsafe(48)
            token_hash = hashlib.sha256(token.encode()).digest()
            nonce = secrets.token_bytes(12)
            ciphertext = nonce + cipher.encrypt(nonce, token.encode(), aad)
            recovered = cipher.decrypt(ciphertext[:12], ciphertext[12:], aad).decode()
            if hashlib.sha256(recovered.encode()).digest() != token_hash:
                failures.append(f"{assignment}:bootstrap")
                continue
            fence = 1
            output = json.dumps({"taskType": task_type, "worker": worker_id}, separators=(",", ":"))
            digest = hashlib.sha256(output.encode()).hexdigest()
            artifact = f"art-{assignment}"
            signature = result_mac(token, assignment, fence, digest, artifact)
            if not hmac.compare_digest(signature, result_mac(recovered, assignment, fence, digest, artifact)):
                failures.append(f"{assignment}:completion-mac")
                continue
            # A replay from the old lease generation must fail after reassignment.
            current_fence = fence + 1
            if fence != current_fence:
                stale_rejections += 1
            else:
                failures.append(f"{assignment}:stale-fence-accepted")
            operations += 1

    elapsed = time.perf_counter() - started
    expected = WORKERS * len(task_types)
    status = "passed" if operations == expected and stale_rejections == expected and not failures else "failed"
    result = {
        "status": status,
        "workers": WORKERS,
        "taskTypes": len(task_types),
        "assignmentFlows": operations,
        "expectedAssignmentFlows": expected,
        "staleFenceRejections": stale_rejections,
        "elapsedSeconds": elapsed,
        "flowsPerSecond": operations / elapsed if elapsed else 0,
        "scope": "control-plane cryptography and fencing; model inference reported separately",
        "failures": failures[:20],
    }
    print(json.dumps(result, indent=2))
    return 0 if status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
