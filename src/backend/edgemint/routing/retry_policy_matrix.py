from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

from edgemint.routing.retry_classifier import RetryClass, classify_failure_code

_QUALITY_FAILURE_CODES: frozenset[str] = frozenset(
    {
        "RESULT_VALIDATION_FAILED",
        "OCR_EMPTY_RESULT",
        "VISION_LOW_CONFIDENCE",
        "RESULT_LOW_CONFIDENCE",
        "RESULT_EMPTY",
        "GOLDEN_VALIDATION_FAILED",
    }
)


@dataclass(frozen=True, slots=True)
class TaskRetryPolicy:
    task_type: str
    retry_class: RetryClass
    quality_failure_retry_class: RetryClass
    executable: bool
    max_automatic_retries: int


@dataclass(frozen=True, slots=True)
class RetryPolicyMatrix:
    spec: dict[str, Any]
    path: Path
    entries: dict[str, TaskRetryPolicy]

    @classmethod
    def load(cls, root: Path | None = None) -> RetryPolicyMatrix:
        repo_root = root or Path(__file__).resolve().parents[4]
        path = repo_root / "dsl" / "policies" / "retry" / "task-retry-matrix-v1.yaml"
        import yaml

        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        spec = document["spec"]
        return cls(spec=spec, path=path, entries=_build_index(spec))

    @property
    def default_max_automatic_retries(self) -> int:
        return int(self.spec.get("defaultMaxAutomaticRetries", 2))

    def entry(self, task_type: str) -> TaskRetryPolicy | None:
        return self.entries.get(task_type)

    def resolve_retry_class(self, *, task_type: str, failure_code: str) -> RetryClass:
        policy = self.entry(task_type)
        if policy is None or not policy.executable:
            return RetryClass.NO_RETRY

        failure_class = classify_failure_code(failure_code)
        if failure_class == RetryClass.NO_RETRY:
            return RetryClass.NO_RETRY

        normalized = failure_code.strip().upper()
        if normalized in _QUALITY_FAILURE_CODES:
            return policy.quality_failure_retry_class
        if failure_class == RetryClass.STRONGER_WORKER:
            return RetryClass.STRONGER_WORKER
        return policy.retry_class


def _build_index(spec: dict[str, Any]) -> dict[str, TaskRetryPolicy]:
    default_retries = int(spec.get("defaultMaxAutomaticRetries", 2))
    index: dict[str, TaskRetryPolicy] = {}
    for row in spec.get("entries", []):
        task_type = str(row["taskType"])
        index[task_type] = TaskRetryPolicy(
            task_type=task_type,
            retry_class=RetryClass(str(row["retryClass"])),
            quality_failure_retry_class=RetryClass(
                str(row.get("qualityFailureRetryClass") or row["retryClass"])
            ),
            executable=bool(row["executable"]),
            max_automatic_retries=int(row.get("maxAutomaticRetries", default_retries)),
        )
    return index


@lru_cache
def get_retry_policy_matrix() -> RetryPolicyMatrix:
    return RetryPolicyMatrix.load()


def catalog_task_types(root: Path | None = None) -> list[str]:
    repo_root = root or Path(__file__).resolve().parents[4]
    import json

    catalog = json.loads((repo_root / "src" / "shared" / "task-types" / "catalog.json").read_text(encoding="utf-8"))
    return [
        str(item["value"])
        for category in catalog["categories"]
        for item in category["types"]
    ]
