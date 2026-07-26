#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tests.oracles.vector_oracles import ORACLES  # noqa: E402

EXPECTED_COUNTS = {
    "pricing-vectors.jsonl": 110000,
    "routing-vectors.jsonl": 100000,
    "reward-vectors.jsonl": 90000,
    "ledger-vectors.jsonl": 90000,
    "task-lifecycle-vectors.jsonl": 70000,
    "fraud-vectors.jsonl": 60000,
    "webhook-vectors.jsonl": 30000,
    "claim-vectors.jsonl": 25000,
    "worker-resume-vectors.jsonl": 20000,
}

errors: list[str] = []
counts: dict[str, int] = {}
for path in sorted((ROOT / "tests/vectors").glob("*.jsonl")):
    count = 0
    ids: set[str] = set()
    oracle = ORACLES.get(path.name)
    if oracle is None:
        errors.append(f"{path.name}: no registered semantic oracle")
        continue
    with path.open(encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            try:
                case = json.loads(line)
            except Exception as exc:
                errors.append(f"{path.name}:{line_no}: invalid JSON: {exc}")
                continue
            count += 1
            case_id = case.get("caseId")
            if not case_id:
                errors.append(f"{path.name}:{line_no}: missing caseId")
            elif case_id in ids:
                errors.append(f"{path.name}:{line_no}: duplicate caseId {case_id}")
            ids.add(case_id)
            try:
                recomputed_entries, recomputed_expected = oracle(case)
            except Exception as exc:
                errors.append(f"{path.name}:{line_no}: oracle execution failed: {exc}")
                continue
            if recomputed_entries is not None and case.get("entries") != recomputed_entries:
                errors.append(f"{path.name}:{line_no}: ledger entries differ from oracle")
            if case.get("expected") != recomputed_expected:
                errors.append(f"{path.name}:{line_no}: expected result differs from oracle")
            if len(errors) >= 500:
                break
    counts[path.name] = count
    if len(errors) >= 500:
        break

for name, expected in EXPECTED_COUNTS.items():
    if counts.get(name) != expected:
        errors.append(f"{name}: expected {expected} cases, got {counts.get(name)}")
for name in counts:
    if name not in EXPECTED_COUNTS:
        errors.append(f"{name}: unexpected vector suite")

result = {
    "files": len(counts),
    "lines": sum(counts.values()),
    "counts": counts,
    "semanticOracles": sorted(ORACLES),
    "errors": len(errors),
}
print(json.dumps(result, ensure_ascii=False, indent=2))
if errors:
    print("\n".join(errors[:500]))
    sys.exit(1)
