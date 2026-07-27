#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tests.oracles.vector_oracles import ORACLES  # noqa: E402

sys.path.insert(0, str(ROOT / "src" / "backend"))
try:
    from edgemint.pricing.engine import compute_price as production_compute_price
except ImportError:  # pragma: no cover
    production_compute_price = None

try:
    from edgemint.routing.engine import evaluate_candidate as production_evaluate_candidate
except ImportError:  # pragma: no cover
    production_evaluate_candidate = None

try:
    from edgemint.rewards.engine import compute_reward as production_compute_reward
except ImportError:  # pragma: no cover
    production_compute_reward = None

try:
    from edgemint.webhooks.engine import evaluate_delivery as production_evaluate_delivery
except ImportError:  # pragma: no cover
    production_evaluate_delivery = None

try:
    from edgemint.fraud.engine import evaluate_fraud as production_evaluate_fraud
except ImportError:  # pragma: no cover
    production_evaluate_fraud = None

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
            if (
                path.name == "pricing-vectors.jsonl"
                and production_compute_price is not None
                and case.get("expected") != production_compute_price(case["input"])
            ):
                errors.append(f"{path.name}:{line_no}: production pricing engine differs from expected")
            if (
                path.name == "reward-vectors.jsonl"
                and production_compute_reward is not None
                and case.get("expected") != production_compute_reward(case["input"])
            ):
                errors.append(f"{path.name}:{line_no}: production reward engine differs from expected")
            if (
                path.name == "routing-vectors.jsonl"
                and production_evaluate_candidate is not None
                and case.get("expected") != production_evaluate_candidate(case["input"])
            ):
                errors.append(f"{path.name}:{line_no}: production routing engine differs from expected")
            if (
                path.name == "webhook-vectors.jsonl"
                and production_evaluate_delivery is not None
                and case.get("expected") != production_evaluate_delivery(case["input"])
            ):
                errors.append(f"{path.name}:{line_no}: production webhook engine differs from expected")
            if (
                path.name == "fraud-vectors.jsonl"
                and production_evaluate_fraud is not None
                and case.get("expected") != production_evaluate_fraud(case["input"])
            ):
                errors.append(f"{path.name}:{line_no}: production fraud engine differs from expected")
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
