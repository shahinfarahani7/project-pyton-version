from dataclasses import dataclass
from .eligibility import RoutingPolicy,WorkerSnapshot,reasons
@dataclass(frozen=True,slots=True)
class RankedWorker:
    worker_id:str; eligible:bool; score:int; ineligibility_reasons:tuple[str,...]
def score(worker:WorkerSnapshot,policy:RoutingPolicy)->RankedWorker:
    blocked=tuple(reasons(worker,policy)); value=sum(worker.feature_bps(name)*weight//10_000 for name,weight in policy.weights_bps.items())
    return RankedWorker(worker.worker_id,not blocked,value,blocked)
