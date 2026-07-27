from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4


@dataclass
class HumanReviewItem:
    review_id: str
    task_id: str
    result_id: str
    reason: str
    status: str
    created_at: datetime
    assigned_reviewer: str | None = None


@dataclass
class HumanReviewQueue:
    items: list[HumanReviewItem] = field(default_factory=list)

    def enqueue(self, *, task_id: str, result_id: str, reason: str) -> HumanReviewItem:
        item = HumanReviewItem(
            review_id=f"hrev_{uuid4().hex[:20]}",
            task_id=task_id,
            result_id=result_id,
            reason=reason,
            status="pending",
            created_at=datetime.now(UTC),
        )
        self.items.append(item)
        return item

    def pending(self) -> list[HumanReviewItem]:
        return [item for item in self.items if item.status == "pending"]

    def resolve(self, review_id: str, *, outcome: str, reviewer: str) -> HumanReviewItem:
        for item in self.items:
            if item.review_id != review_id:
                continue
            if item.status != "pending":
                raise ValueError("review already resolved")
            item.status = outcome
            item.assigned_reviewer = reviewer
            return item
        raise KeyError(review_id)

    def as_dict(self) -> list[dict[str, Any]]:
        return [
            {
                "reviewId": item.review_id,
                "taskId": item.task_id,
                "resultId": item.result_id,
                "reason": item.reason,
                "status": item.status,
                "createdAt": item.created_at.isoformat(),
                "assignedReviewer": item.assigned_reviewer,
            }
            for item in self.items
        ]
