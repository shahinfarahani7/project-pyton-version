from dataclasses import dataclass
from enum import StrEnum
from uuid import UUID
class DomainError(ValueError): pass
class TaskLifecycleStatus(StrEnum):
    DRAFT="draft";SUBMITTED="submitted";ACTIVE="active";COMPLETED="completed";FAILED="failed";CANCELLED="cancelled";EXPIRED="expired";DISPUTED="disputed"
class AttemptStatus(StrEnum):
    CREATED="created";MATCHING="matching";LEASED="leased";RUNNING="running";RESULT_SUBMITTED="result_submitted";VERIFYING="verifying";SUCCEEDED="succeeded";FAILED="failed";ABANDONED="abandoned";EXPIRED="expired"
@dataclass(slots=True)
class TaskAggregate:
    id:UUID;version:int=0;lifecycle_status:TaskLifecycleStatus=TaskLifecycleStatus.DRAFT;current_revision_id:UUID|None=None
@dataclass(slots=True)
class AttemptAggregate:
    version:int=0;status:AttemptStatus=AttemptStatus.CREATED
