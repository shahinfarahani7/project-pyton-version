#!/usr/bin/env python3
from pathlib import Path
import yaml,json,sys,re
ROOT=Path(__file__).resolve().parents[1];errors=[]
ops={}
for p in (ROOT/'contracts/openapi').glob('*.yaml'):
 d=yaml.safe_load(p.read_text(encoding='utf-8'))
 for path,item in d['paths'].items():
  for method,o in item.items():
   if method in ['get','post','put','patch','delete']:
    ops[o['operationId']]={'method':method.upper(),'path':path,'permissions':o.get('x-required-permissions',[]),
      'requestRequired':bool(o.get('requestBody',{}).get('required')),'responses':[str(x) for x in o.get('responses',{})]}
samples={}
for p in (ROOT/'samples/by-operation').glob('*.json'):
 try:d=json.loads(p.read_text(encoding='utf-8'))
 except Exception as exc:errors.append(f'{p.name}: invalid JSON {exc}');continue
 oid=d.get('operationId')
 if oid in samples:errors.append(f'duplicate sample {oid}')
 samples[oid]=(p,d)
for oid,x in ops.items():
 if oid not in samples:errors.append('missing sample '+oid);continue
 p,d=samples[oid];req=d.get('request',{});expected=d.get('expected',{})
 if req.get('method')!=x['method']:errors.append(f'{oid}: method differs from OpenAPI')
 if req.get('path')!=x['path']:errors.append(f'{oid}: path differs from OpenAPI')
 params=set(re.findall(r'\{([^}]+)\}',x['path']))
 if set(req.get('pathParameters',{}))!=params:errors.append(f'{oid}: path parameter sample mismatch')
 headers=req.get('headers',{})
 if 'X-Request-Id' not in headers:errors.append(f'{oid}: missing X-Request-Id')
 mutation=x['method']!='GET'
 if mutation and 'Idempotency-Key' not in headers:errors.append(f'{oid}: mutation sample missing Idempotency-Key')
 if not mutation and 'Idempotency-Key' in headers:errors.append(f'{oid}: safe read must not imply idempotency key')
 if x['requestRequired'] and req.get('body') is None:errors.append(f'{oid}: required request body sample missing')
 success=next((s for s in x['responses'] if s.startswith('2')),None)
 if expected.get('successStatus')!=success:errors.append(f'{oid}: success status differs from OpenAPI')
 if expected.get('mutationIsIdempotent')!=mutation:errors.append(f'{oid}: mutationIsIdempotent mismatch')
 if expected.get('requiredPermissions')!=x['permissions']:errors.append(f'{oid}: requiredPermissions differ from OpenAPI')
 text=json.dumps(d)
 if re.search(r'(?i)(sk_live|-----BEGIN PRIVATE KEY-----|Bearer\s+(?!customer_access_token_redacted|worker_access_token_redacted|operator_access_token_redacted))',text):
  errors.append(f'{oid}: sample appears to contain an unredacted credential')
for oid,(p,d) in samples.items():
 if oid not in ops:errors.append('sample for unknown operation '+str(oid))
journeys=list((ROOT/'samples/journeys').glob('*.json'))
for p in journeys:
 try:d=json.loads(p.read_text(encoding='utf-8'))
 except Exception as exc:errors.append(f'{p.name}: invalid JSON {exc}');continue
 sequence=d.get('orderedOperations',[])
 if not sequence:errors.append(f'{p.name}: orderedOperations empty')
 for oid in sequence:
  if oid not in ops:errors.append(f'{p.name}: unknown operation {oid}')
 if len(sequence)!=len(list(sequence)):errors.append(f'{p.name}: duplicate operation in ordered journey')
print(json.dumps({'operations':len(ops),'operationSamples':len(samples),'journeys':len(journeys),'errors':len(errors)},indent=2))
if errors:print('\n'.join(errors[:500]));sys.exit(1)
