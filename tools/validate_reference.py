#!/usr/bin/env python3
from pathlib import Path
import yaml,re,json,sys,ast
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'reference/python';errors=[]
files=[p for p in REF.rglob('*.py') if p.is_file()]
for p in files:
 t=p.read_text(encoding='utf-8')
 if re.search(r'NotImplementedError|\bTODO\b|\bTBD\b',t):errors.append(f'{p.relative_to(ROOT)}: placeholder remains')
 try:ast.parse(t)
 except SyntaxError as exc:errors.append(f'{p.relative_to(ROOT)}: syntax error {exc}')
for rel in ['reference/python/building_blocks/money.py','reference/python/ledger/ledger_writer.py','reference/python/pricing/pricing_engine.py']:
 t=(ROOT/rel).read_text()
 if re.search(r'\b(float|Decimal)\b',t):errors.append(f'{rel}: inexact financial type forbidden')
def states(rel):
 d=yaml.safe_load((ROOT/rel).read_text());return {x['name'].replace('_','').lower() for x in d['spec']['states']}
agg=(ROOT/'reference/python/tasks/aggregates.py').read_text()
for enum,wf in [('TaskLifecycleStatus','dsl/workflows/task-lifecycle.yaml'),('AttemptStatus','dsl/workflows/attempt-lifecycle.yaml')]:
 m=re.search(r'class\s+'+enum+r'\(StrEnum\):(.*?)(?=\nclass |\n@dataclass)',agg,re.S)
 actual=set(re.findall(r'=\s*"([a-z_]+)"',m.group(1) if m else ''))
 if {x.replace('_','') for x in actual}!={x.replace('_','') for x in states(wf)}:errors.append(f'{enum} differs from {wf}')
pb=yaml.safe_load((ROOT/'dsl/policies/pricing/public-eur-2026q3-v2.yaml').read_text())['spec'];pt=(ROOT/'reference/python/pricing/pricing_engine.py').read_text()
for m in pb['orderedModifiers']:
 if f'"{m}"' not in pt:errors.append(f'PricingEngine missing modifier {m}')
for token in ['minimum_charge_micros','apply_bps','ceiling_div']:
 if token not in pt:errors.append('PricingEngine missing '+token)
rt=(ROOT/'reference/python/routing/eligibility.py').read_text()+(ROOT/'reference/python/routing/deterministic_router.py').read_text()
for token in ['heartbeat_maximum_age_seconds','minimum_trust_milli','minimum_battery_percent','disallowed_thermal_states','require_attestation_for_paid_tasks','require_current_consent','require_available_status','require_model_digest_match','require_runtime_abi_match','respect_customer_region','respect_worker_network_policy','network_policy_allowed','weights_bps']:
 if token not in rt:errors.append('Routing reference missing '+token)
fn=(ROOT/'reference/python/routing/feature_normalizer.py').read_text();qs=(ROOT/'reference/python/routing/queue_selector.py').read_text()
for token in ['model_locality','predicted_latency','price_efficiency','reliability','clamp']:
 if token not in fn:errors.append('FeatureNormalizer missing '+token)
for token in ['fairness_deficit','priority_bps','aging_boost_bps','deadline_at','submitted_at','task_id']:
 if token not in qs:errors.append('QueueSelector missing '+token)
fg=(ROOT/'reference/python/workers/fence_guard.py').read_text()
for token in ['ASSIGNMENT_STALE_FENCE','LEASE_EXPIRED']:
 if token not in fg:errors.append('FenceGuard missing '+token)
print(json.dumps({'referenceFiles':len(files),'errors':errors},indent=2));sys.exit(1 if errors else 0)
