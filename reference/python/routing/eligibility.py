from dataclasses import dataclass
@dataclass(frozen=True, slots=True)
class RoutingPolicy:
    heartbeat_maximum_age_seconds:int; minimum_trust_milli:int; minimum_battery_percent:int; disallowed_thermal_states:frozenset[str]
    require_attestation_for_paid_tasks:bool; require_current_consent:bool; require_available_status:bool; require_model_digest_match:bool
    require_runtime_abi_match:bool; respect_customer_region:bool; respect_worker_network_policy:bool; weights_bps:dict[str,int]
@dataclass(frozen=True, slots=True)
class WorkerSnapshot:
    worker_id:str; features_bps:dict[str,int]; heartbeat_age_seconds:int; battery_percent:int; thermal_state:str; attested:bool
    consent_current:bool; available:bool; schedule_eligible:bool; capacity_available:bool; model_digest_match:bool; runtime_abi_match:bool
    region_allowed:bool; network_policy_allowed:bool; device_tier_sufficient:bool; free_ram_bytes:int; required_ram_bytes:int
    free_storage_bytes:int; required_storage_bytes:int
    def feature_bps(self,name:str)->int:
        if name not in self.features_bps: raise ValueError(f"MISSING_ROUTING_FEATURE:{name}")
        return self.features_bps[name]
def reasons(w:WorkerSnapshot,p:RoutingPolicy)->list[str]:
    result=[]
    if w.heartbeat_age_seconds>p.heartbeat_maximum_age_seconds: result.append("STALE_HEARTBEAT")
    if w.feature_bps("trust")<p.minimum_trust_milli*10: result.append("TRUST_TOO_LOW")
    if w.battery_percent<p.minimum_battery_percent: result.append("BATTERY_TOO_LOW")
    if w.thermal_state in p.disallowed_thermal_states: result.append("THERMAL_BLOCK")
    if p.require_attestation_for_paid_tasks and not w.attested: result.append("ATTESTATION_REQUIRED")
    if p.require_current_consent and not w.consent_current: result.append("CONSENT_REQUIRED")
    if p.require_available_status and not w.available: result.append("WORKER_UNAVAILABLE")
    if not w.schedule_eligible: result.append("WORKER_OUTSIDE_AVAILABLE_SCHEDULE")
    if not w.capacity_available: result.append("WORKER_CAPACITY_EXHAUSTED")
    if p.require_model_digest_match and not w.model_digest_match: result.append("MODEL_DIGEST_MISMATCH")
    if p.require_runtime_abi_match and not w.runtime_abi_match: result.append("RUNTIME_ABI_MISMATCH")
    if p.respect_customer_region and not w.region_allowed: result.append("REGION_NOT_ALLOWED")
    if p.respect_worker_network_policy and not w.network_policy_allowed: result.append("NETWORK_POLICY_BLOCKED")
    if not w.device_tier_sufficient: result.append("DEVICE_TIER_INSUFFICIENT")
    if w.free_ram_bytes<w.required_ram_bytes: result.append("RESOURCE_MEMORY_PRESSURE")
    if w.free_storage_bytes<w.required_storage_bytes: result.append("INSUFFICIENT_STORAGE")
    return result
