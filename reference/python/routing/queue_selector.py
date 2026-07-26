from dataclasses import dataclass
from datetime import UTC,datetime
@dataclass(frozen=True,slots=True)
class QueuedAttempt:
    attempt_id:str; workspace_id:str; task_id:str; fairness_deficit:int; consecutive_assignments:int; estimated_cost_units:int; priority_bps:int
    deadline_at:datetime|None; submitted_at:datetime; assignment_history_count:int
    def aging_boost_bps(self,now:datetime)->int:return min(2_000,max(0,int((now-self.submitted_at).total_seconds()//60))*25)
@dataclass(frozen=True,slots=True)
class QueueSelectionPolicy:
    candidate_window_size:int; maximum_consecutive_assignments_per_workspace:int; starvation_limit_seconds:int; max_worker_reassignments:int
def select(candidates:list[QueuedAttempt],now:datetime,policy:QueueSelectionPolicy)->QueuedAttempt|None:
    eligible=[x for x in candidates if x.assignment_history_count<=policy.max_worker_reassignments]
    def key(x:QueuedAttempt):
        waiting=max(0,int((now-x.submitted_at).total_seconds())); starved=waiting>=policy.starvation_limit_seconds
        consecutive=x.consecutive_assignments>=policy.maximum_consecutive_assignments_per_workspace
        deadline=x.deadline_at or datetime.max.replace(tzinfo=UTC)
        return (0 if starved else 1,x.submitted_at if starved else datetime.max.replace(tzinfo=UTC),1 if consecutive else 0,-x.fairness_deficit,-(x.priority_bps+x.aging_boost_bps(now)),deadline,x.submitted_at,x.task_id,x.attempt_id)
    return min(eligible[:policy.candidate_window_size],key=key,default=None)
