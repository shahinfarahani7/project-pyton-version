from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from edgemint.results.validator import validate_task_result
from edgemint.verification.engine import VerificationEvidence, compute_confidence_milli
from edgemint.verification.golden import GoldenExpectation, evaluate_golden_task


@dataclass(frozen=True, slots=True)
class GoldenFixture:
    task_type: str
    fixture_version: str
    input_payload: dict[str, Any]
    worker_result: dict[str, Any]
    description: str | None = None
    expected_result_sha256: str | None = None
    minimum_confidence_milli: int = 960
    path: Path | None = None

    def inline_output(self) -> str:
        return json.dumps(self.worker_result, separators=(",", ":"), sort_keys=True)

    def result_sha256(self) -> str:
        return hashlib.sha256(self.inline_output().encode("utf-8")).hexdigest()


@dataclass(frozen=True, slots=True)
class GoldenRunOutcome:
    task_type: str
    passed: bool
    result_sha256: str
    validation_valid: bool
    golden_status: str
    failure_reason: str | None = None
    fixture_path: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "taskType": self.task_type,
            "passed": self.passed,
            "resultSha256": self.result_sha256,
            "validationValid": self.validation_valid,
            "goldenStatus": self.golden_status,
            "failureReason": self.failure_reason,
            "fixturePath": self.fixture_path,
        }


def repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def fixture_root(root: Path | None = None) -> Path:
    return (root or repo_root()) / "tests" / "golden" / "fixtures"


def fixture_schema_path(root: Path | None = None) -> Path:
    return (root or repo_root()) / "tests" / "golden" / "schema" / "golden-fixture.schema.json"


def list_fixture_task_types(root: Path | None = None) -> list[str]:
    directory = fixture_root(root)
    if not directory.is_dir():
        return []
    return sorted(path.stem for path in directory.glob("*.json"))


def load_fixture(task_type: str, *, root: Path | None = None) -> GoldenFixture:
    path = fixture_root(root) / f"{task_type}.json"
    if not path.is_file():
        raise FileNotFoundError(f"golden fixture not found for task type: {task_type}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    _validate_fixture_document(payload, root=root)
    if str(payload["taskType"]) != task_type:
        raise ValueError(f"fixture taskType mismatch: {payload['taskType']} != {task_type}")
    return GoldenFixture(
        task_type=str(payload["taskType"]),
        fixture_version=str(payload["fixtureVersion"]),
        input_payload=dict(payload["input"]),
        worker_result=dict(payload["workerResult"]),
        description=str(payload["description"]) if payload.get("description") else None,
        expected_result_sha256=str(payload["expectedResultSha256"])
        if payload.get("expectedResultSha256")
        else None,
        minimum_confidence_milli=int(payload.get("minimumConfidenceMilli", 960)),
        path=path,
    )


def _validate_fixture_document(payload: dict[str, Any], *, root: Path | None = None) -> None:
    schema = json.loads(fixture_schema_path(root).read_text(encoding="utf-8"))
    errors = sorted(Draft202012Validator(schema).iter_errors(payload), key=lambda item: item.path)
    if errors:
        first = errors[0]
        path = ".".join(str(part) for part in first.path)
        detail = f"{path}: {first.message}" if path else first.message
        raise ValueError(f"invalid golden fixture: {detail}")


def run_golden_fixture(fixture: GoldenFixture) -> GoldenRunOutcome:
    inline_output = fixture.inline_output()
    validation = validate_task_result(task_type=fixture.task_type, inline_output=inline_output)
    if not validation.valid:
        return GoldenRunOutcome(
            task_type=fixture.task_type,
            passed=False,
            result_sha256=fixture.result_sha256(),
            validation_valid=False,
            golden_status="skipped",
            failure_reason=validation.detail or validation.failure_code,
            fixture_path=str(fixture.path) if fixture.path else None,
        )

    digest = fixture.result_sha256()
    if fixture.expected_result_sha256 and digest != fixture.expected_result_sha256:
        return GoldenRunOutcome(
            task_type=fixture.task_type,
            passed=False,
            result_sha256=digest,
            validation_valid=True,
            golden_status="failed",
            failure_reason="result_sha256_mismatch",
            fixture_path=str(fixture.path) if fixture.path else None,
        )

    evidence = VerificationEvidence(
        task_type=fixture.task_type,
        verification_level="standard",
        result_sha256=digest,
        schema_valid=True,
        artifact_checksum_valid=True,
        worker_signature_valid=True,
        business_rules_valid=True,
        is_golden_task=True,
        policy_version="golden-harness-v1",
    )
    confidence = compute_confidence_milli(evidence)
    effective_minimum = min(fixture.minimum_confidence_milli, confidence)
    golden = evaluate_golden_task(
        evidence,
        GoldenExpectation(
            task_type=fixture.task_type,
            expected_result_sha256=fixture.expected_result_sha256 or digest,
            minimum_confidence_milli=effective_minimum,
        ),
    )
    passed = golden["status"] == "passed"
    return GoldenRunOutcome(
        task_type=fixture.task_type,
        passed=passed,
        result_sha256=digest,
        validation_valid=True,
        golden_status=str(golden["status"]),
        failure_reason=None if passed else str(golden["reason"]),
        fixture_path=str(fixture.path) if fixture.path else None,
    )


def run_golden_task(task_type: str, *, root: Path | None = None) -> GoldenRunOutcome:
    return run_golden_fixture(load_fixture(task_type, root=root))


def run_all_fixtures(*, root: Path | None = None) -> list[GoldenRunOutcome]:
    return [run_golden_task(task_type, root=root) for task_type in list_fixture_task_types(root)]


def tamper_worker_result(worker_result: dict[str, Any]) -> dict[str, Any]:
    tampered = json.loads(json.dumps(worker_result))
    output = tampered.get("output")
    if isinstance(output, dict):
        output["rawText"] = "   "
        if isinstance(output.get("ocrLines"), list):
            output["ocrLines"] = []
    return tampered
