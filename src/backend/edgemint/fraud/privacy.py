from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

RETAINED_RECORD_CLASSES = frozenset({"financial_record", "audit_record"})


@dataclass
class PrivacyStore:
    profiles: dict[str, dict[str, Any]] = field(default_factory=dict)
    device_links: dict[str, list[dict[str, str]]] = field(default_factory=dict)
    dsar_requests: list[dict[str, Any]] = field(default_factory=list)
    deletion_log: list[dict[str, Any]] = field(default_factory=list)

    def minimize_profile(self, *, subject_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        minimized = {
            "subjectId": subject_id,
            "country": payload.get("country"),
            "tier": payload.get("tier"),
        }
        self.profiles[subject_id] = minimized
        return minimized

    def submit_dsar(self, *, subject_id: str, request_type: str) -> dict[str, Any]:
        request = {
            "requestId": f"dsar_{uuid4().hex[:16]}",
            "subjectId": subject_id,
            "requestType": request_type,
            "submittedAt": datetime.now(UTC).isoformat(),
            "status": "accepted",
        }
        self.dsar_requests.append(request)
        return request

    def delete_subject_data(
        self,
        *,
        subject_id: str,
        retained_records: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        retained = retained_records or []
        deleted_fields: list[str] = []
        if subject_id in self.profiles:
            del self.profiles[subject_id]
            deleted_fields.append("profile")
        if subject_id in self.device_links:
            del self.device_links[subject_id]
            deleted_fields.append("device_links")
        preserved = [item for item in retained if item.get("class") in RETAINED_RECORD_CLASSES]
        entry = {
            "deletionId": f"del_{uuid4().hex[:16]}",
            "subjectId": subject_id,
            "deletedAt": datetime.now(UTC).isoformat(),
            "deletedStores": deleted_fields,
            "preservedRecords": len(preserved),
        }
        self.deletion_log.append(entry)
        return entry
