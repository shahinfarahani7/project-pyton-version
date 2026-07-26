def clamp(value:int)->int:return max(0,min(10_000,value))
def model_locality(loaded:bool,installed:bool,verified_cache:bool)->int:return 10_000 if loaded else 8_500 if installed else 7_000 if verified_cache else 0
def trust(trust_score_bps:int)->int:return clamp(trust_score_bps)
def predicted_latency(predicted_p95_ms:int,deadline_budget_ms:int)->int:return clamp(10_000-predicted_p95_ms*10_000//max(deadline_budget_ms,1))
def battery_charging(charging:bool)->int:return 10_000 if charging else 3_000
def network(value:str)->int:return {"ethernet":10_000,"wifi":8_500,"cellular":5_000}.get(value,0)
def regional_compliance(allowed:bool)->int:return 10_000 if allowed else 0
def price_efficiency(predicted_cost_micros:int,budget_micros:int)->int:return clamp(10_000-predicted_cost_micros*10_000//max(budget_micros,1))
def reliability(completion_rate_bps:int,on_time_rate_bps:int)->int:return clamp(completion_rate_bps*6_000//10_000+on_time_rate_bps*4_000//10_000)
