#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import yaml,json,sys,collections,re
ROOT=Path(__file__).resolve().parents[1]
errors=[]

def load(p):return yaml.safe_load(p.read_text(encoding='utf-8'))
def ref_name(ref):return ref.split('/')[-1].split('@')[0]
def norm(s):return s.lower()

# OpenAPI registry
operations={}
for p in sorted((ROOT/'contracts/openapi').glob('*.yaml')):
 d=load(p)
 api={'edgemint-public-api.yaml':'public','edgemint-worker-api.yaml':'worker','edgemint-operations-api.yaml':'operations'}[p.name]
 for path,item in d.get('paths',{}).items():
  for method,o in item.items():
   if method not in {'get','post','put','patch','delete'}:continue
   oid=o['operationId']
   operations[oid]={'api':api,'method':method.upper(),'path':path,'permissions':o.get('x-required-permissions',[]),'responses':[str(x) for x in o.get('responses',{})]}
# Catalogs
ed=load(ROOT/'dsl/catalog/events/event-catalog-v2.yaml');event_names={x['name'] for x in ed['spec']['events']}
ec=load(ROOT/'dsl/catalog/errors/error-catalog-v2.yaml');error_codes={x['code'] for x in ec['spec']['errors']}
# SQL tables
sql='\n'.join(p.read_text(encoding='utf-8') for p in sorted((ROOT/'database/sql').glob('*.sql')))
tables=set(re.findall(r'CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+(?:(?:public|eventing|security|audit|dbo)\.)?([a-zA-Z_][a-zA-Z0-9_]*)',sql,re.I))
# DSL documents
requirements={};usecases={};scenarios={};opcontracts={}
for p in sorted((ROOT/'dsl/requirements').glob('*.yaml')):
 d=load(p);requirements[norm(d['metadata']['name'])]=(p,d)
for p in sorted((ROOT/'dsl/use-cases').glob('*.yaml')):
 d=load(p);usecases[d['metadata']['name']]=(p,d)
for p in sorted((ROOT/'dsl/scenarios').glob('*.yaml')):
 d=load(p);scenarios[d['metadata']['name']]=(p,d)
for p in sorted((ROOT/'dsl/operation-contracts').glob('*.yaml')):
 d=load(p);opcontracts[d['spec']['operationId']]=(p,d)

req_to_uc=collections.defaultdict(list);uc_to_scenarios=collections.defaultdict(list);op_to_uc=collections.defaultdict(list)
# Use-case semantic validation
for uname,(p,d) in usecases.items():
 s=d['spec'];uid=s['id'];trace=s['trace'];impl=s['implementation'];rel=p.relative_to(ROOT)
 for r in trace['requirements']:
  if norm(r) not in requirements:errors.append(f'{rel}: unknown requirement {r}')
  else:req_to_uc[norm(r)].append(uname)
 for oid in trace['apiOperations']:
  if oid.startswith('control:'):continue
  if oid not in operations:errors.append(f'{rel}: unknown OpenAPI operation {oid}')
  else:op_to_uc[oid].append(uname)
 for ev in trace['events']:
  if ev not in event_names:errors.append(f'{rel}: unknown canonical event {ev}')
 for ent in trace['entities']:
  if not ent.startswith('control:') and ent not in tables:errors.append(f'{rel}: entity/table does not exist {ent}')
 for code in impl['errorCodes']:
  if code not in error_codes:errors.append(f'{rel}: error code not in ErrorCatalog {code}')
 expected_transport=[];permissions=[]
 for oid in trace['apiOperations']:
  if oid.startswith('control:'):expected_transport.append({'operationId':oid,'method':'CONTROL','path':'internal-control'})
  else:
   x=operations[oid];expected_transport.append({'operationId':oid,'method':x['method'],'path':x['path']});permissions += x['permissions']
 if impl['transport']!=expected_transport:errors.append(f'{rel}: implementation.transport differs from OpenAPI trace')
 for perm in permissions:
  if perm not in impl['authorization']['permissionSource']:errors.append(f'{rel}: authorization omits permission {perm}')
 control_mutation=uid=='UC-053'
 mutation=control_mutation or any(x['method'] not in {'GET','CONTROL'} for x in expected_transport)
 expected_writes=[] if not mutation else [x for x in trace['entities'] if not x.startswith('control:')]
 expected_events=trace['events'] if mutation else []
 if impl['transaction']['writes']!=expected_writes:errors.append(f'{rel}: transaction writes must exactly match trace entities for mutation/read')
 if impl['transaction']['outboxEvents']!=expected_events:errors.append(f'{rel}: outbox events must exactly match trace events for mutation/read')
 expected_idem='required' if mutation else 'not_applicable'
 if impl['idempotency']['mode']!=expected_idem:errors.append(f'{rel}: idempotency mode must be {expected_idem}')
 if mutation and not any('IDEMPOTENCY_CONFLICT'==x for x in impl['errorCodes']):errors.append(f'{rel}: mutation must declare IDEMPOTENCY_CONFLICT')
 if impl['concurrency'].get('fenceRequired') and not any(x in impl['errorCodes'] for x in ['ASSIGNMENT_STALE_FENCE']):errors.append(f'{rel}: fenced operation must expose ASSIGNMENT_STALE_FENCE')

# Scenario-to-use-case exact alignment.
for sname,(p,d) in scenarios.items():
 s=d['spec'];ref=s.get('useCaseRef');rel=p.relative_to(ROOT)
 if not ref:continue  # state-machine transition scenario
 uname=ref_name(ref)
 if uname not in usecases:errors.append(f'{rel}: unknown use case {ref}');continue
 uc=usecases[uname][1]['spec'];uc_to_scenarios[uname].append(sname)
 if s.get('fixtures',{}).get('operationIds')!=uc['trace']['apiOperations']:errors.append(f'{rel}: fixture operationIds differ from use case')
 if s.get('fixtures',{}).get('requirements')!=uc['trace']['requirements']:errors.append(f'{rel}: fixture requirements differ from use case')
 if s.get('fixtures',{}).get('actor') not in uc['actors']:errors.append(f'{rel}: fixture actor not in use-case actors')
 if s['mode']=='success':
  if s['expectedErrorCode'] is not None:errors.append(f'{rel}: success scenario must have null expectedErrorCode')
  if s['expectedEvents']!=uc['implementation']['transaction']['outboxEvents']:errors.append(f'{rel}: success events differ from use-case outbox events')
 elif s['mode']=='failure':
  if s['expectedEvents']!=[]:errors.append(f'{rel}: failure scenario must not expect domain events')
  if s['expectedErrorCode'] not in uc['implementation']['errorCodes']:errors.append(f'{rel}: failure code not declared by use case')
 else:errors.append(f'{rel}: use-case scenario mode must be success or failure')

for r in requirements:
 if not req_to_uc[r]:errors.append(f'requirement without use case: {r}')
for u in usecases:
 modes=[scenarios[x][1]['spec']['mode'] for x in uc_to_scenarios[u]]
 if modes.count('success')<1 or modes.count('failure')<1:errors.append(f'use case missing success/failure scenarios: {u}')

# One machine-readable OperationContract for every OpenAPI operation.
if set(opcontracts)!=set(operations):
 errors.append(f'OperationContract/OpenAPI mismatch missing={sorted(set(operations)-set(opcontracts))} extra={sorted(set(opcontracts)-set(operations))}')
for oid,x in operations.items():
 if oid not in opcontracts:continue
 p,d=opcontracts[oid];s=d['spec'];rel=p.relative_to(ROOT)
 for field in ['api','method','path']:
  if s[field]!=x[field]:errors.append(f'{rel}: {field} differs from OpenAPI')
 if s['permissions']!=x['permissions']:errors.append(f'{rel}: permissions differ from OpenAPI')
 if s['responseStatuses']!=x['responses']:errors.append(f'{rel}: response status set/order differs from OpenAPI')
 mutation=x['method']!='GET'
 if s['idempotency']['required']!=mutation:errors.append(f'{rel}: idempotency.required must equal mutation={mutation}')
 if s['transaction']['mode']!=('command' if mutation else 'read_only'):errors.append(f'{rel}: transaction mode mismatch')
 if not mutation and (s['transaction']['writes'] or s['transaction']['domainEvents']):errors.append(f'{rel}: safe read must have no writes/events')
 for ent in s['transaction']['writes']:
  if ent not in tables:errors.append(f'{rel}: unknown write entity {ent}')
 for ev in s['transaction']['domainEvents']:
  if ev not in event_names:errors.append(f'{rel}: unknown event {ev}')
 for code in s['errorCodes']:
  if code not in error_codes:errors.append(f'{rel}: unknown error {code}')
 expected_refs=sorted(f"UseCase/{usecases[u][1]['metadata']['name']}@{usecases[u][1]['metadata']['version']}" for u in op_to_uc.get(oid,[]))
 if s['useCaseRefs']!=expected_refs:errors.append(f'{rel}: useCaseRefs differ from trace index')
 expected_class='business_use_case' if expected_refs else ('supporting_query' if not mutation else 'supporting_command')
 if s['classification']!=expected_class:errors.append(f'{rel}: classification must be {expected_class}')

rows=[]
for r in sorted(requirements):
 linked=sorted(req_to_uc[r]);scs=sorted({sc for u in linked for sc in uc_to_scenarios[u]})
 rows.append({'requirement':r,'useCases':linked,'scenarios':scs})
oprows=[]
for oid in sorted(operations):
 op=operations[oid];oc=opcontracts.get(oid,(None,{}))[1].get('spec',{})
 oprows.append({'operationId':oid,'api':op['api'],'method':op['method'],'path':op['path'],'classification':oc.get('classification'),'useCases':sorted(op_to_uc.get(oid,[]))})
out={'requirements':len(requirements),'useCases':len(usecases),'useCaseScenarios':sum(len(v) for v in uc_to_scenarios.values()),
 'allScenarios':len(scenarios),'openApiOperations':len(operations),'operationContracts':len(opcontracts),'sqlTables':len(tables),
 'rows':rows,'operationRows':oprows,'errors':errors}
(ROOT/'build').mkdir(exist_ok=True);(ROOT/'build/traceability.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8')
# Human-readable matrix
md=['# EdgeMint Traceability Matrix','','Generated by `tools/validate_traceability.py`; do not hand-edit.','',
 '## Coverage summary','',f'- Requirements: **{len(requirements)}**',f'- Business use cases: **{len(usecases)}**',
 f'- Use-case scenarios: **{sum(len(v) for v in uc_to_scenarios.values())}**',f'- OpenAPI operations: **{len(operations)}**',
 f'- Operation contracts: **{len(opcontracts)}**',f'- SQL tables: **{len(tables)}**','',
 '## Requirement → use case → scenario','','| Requirement | Use cases | Scenarios |','|---|---|---|']
for row in rows:md.append(f"| `{row['requirement']}` | {', '.join('`'+x+'`' for x in row['useCases'])} | {', '.join('`'+x+'`' for x in row['scenarios'])} |")
md += ['','## OpenAPI operation coverage','','| Operation | API | Method/path | Classification | Use cases |','|---|---|---|---|---|']
for row in oprows:md.append(f"| `{row['operationId']}` | {row['api']} | `{row['method']} {row['path']}` | {row['classification']} | {', '.join('`'+x+'`' for x in row['useCases']) or 'OpenAPI + OperationContract'} |")
md += ['','## Validation result','',f"- Errors: **{len(errors)}**"]
(ROOT/'docs/06-implementation/TRACEABILITY-MATRIX.md').write_text('\n'.join(md)+'\n',encoding='utf-8')
print(json.dumps({k:out[k] for k in ['requirements','useCases','useCaseScenarios','allScenarios','openApiOperations','operationContracts','sqlTables'] }|{'errors':len(errors)},indent=2))
if errors:
 print('\n'.join(errors[:500]));sys.exit(1)
