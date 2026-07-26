#!/usr/bin/env python3
from pathlib import Path
import yaml,json,sys,collections,re
from jsonschema import Draft202012Validator
ROOT=Path(__file__).resolve().parents[1]; DSL=ROOT/'dsl'; errors=[]; docs=[]
for p in sorted(DSL.rglob('*.yaml')):
    if 'schemas' in p.parts: continue
    try:d=yaml.safe_load(p.read_text(encoding='utf-8'))
    except Exception as e: errors.append(f'{p.relative_to(ROOT)} YAML: {e}');continue
    if not isinstance(d,dict) or not d.get('kind'):continue
    docs.append((p,d)); sp=DSL/'schemas'/f"{d['kind'].lower()}.schema.json"
    if not sp.exists():errors.append(f'{p.relative_to(ROOT)} missing schema {sp.name}');continue
    s=json.loads(sp.read_text());
    for e in Draft202012Validator(s).iter_errors(d): errors.append(f"{p.relative_to(ROOT)} schema {'.'.join(map(str,e.path))}: {e.message}")
# uniqueness and indexes
ids={}; names=collections.defaultdict(set)
for p,d in docs:
    key=(d['kind'],d['metadata']['name'],d['metadata']['version'])
    if key in ids: errors.append(f'duplicate identity {key}: {p} and {ids[key]}')
    ids[key]=p;names[d['kind']].add(d['metadata']['name'])
# Canonical event registry
event_names=set(); event_types=set()
for p,d in docs:
    if d['kind']=='EventCatalog':
        for event in d['spec']['events']:
            if event['name'] in event_names: errors.append(f'{p.relative_to(ROOT)}: duplicate event name {event["name"]}')
            if event['type'] in event_types: errors.append(f'{p.relative_to(ROOT)}: duplicate event type {event["type"]}')
            expected_type=f'io.edgemint.{event["name"]}.v1'
            if event['type']!=expected_type: errors.append(f'{p.relative_to(ROOT)}: event type must be {expected_type}')
            if event['name'].startswith('io.edgemint.'): errors.append(f'{p.relative_to(ROOT)}: event name must not include namespace prefix')
            event_names.add(event['name']); event_types.add(event['type'])
# semantic invariants
for p,d in docs:
    k=d['kind'];s=d['spec'];rel=p.relative_to(ROOT)
    if k=='PriceBook':
        tasks=set()
        for r in s['rules']:
            if r['taskType'] in tasks:errors.append(f'{rel}: duplicate price rule {r["taskType"]}')
            tasks.add(r['taskType'])
            for f in ['quantum','unitPriceMicros','minimumChargeMicros']:
                if not isinstance(r[f],int) or r[f]<=0:errors.append(f'{rel}: {f} must be positive integer')
        if set(s['orderedModifiers'])!=set(s['multipliersBps']):errors.append(f'{rel}: modifier keys mismatch')
        for group,vals in s['multipliersBps'].items():
            if any(not isinstance(v,int) or v<=0 for v in vals.values()):errors.append(f'{rel}: nonpositive BPS in {group}')
    if k=='RoutingPolicy':
        if sum(s['score']['weightsBps'].values())!=10000:errors.append(f'{rel}: routing weights must sum 10000')
    if k=='FraudPolicy':
        if s['scoreScaleBps'] != 10000: errors.append(f'{rel}: fraud score scale must be 10000')
        thresholds=[x['minimumScoreBps'] for x in s['actionBands']]
        if thresholds != sorted(thresholds, reverse=True): errors.append(f'{rel}: fraud action bands must be descending')
        if thresholds[-1] != 0: errors.append(f'{rel}: fraud action bands must include zero floor')
    if k=='StateMachine':
        states={x['name'] for x in s['states']}
        pairs=set()
        for t in s['transitions']:
            if t['from'] not in states or t['to'] not in states:errors.append(f'{rel}: transition references missing state')
            pair=(t['from'],t['to'])
            if pair in pairs:errors.append(f'{rel}: duplicate transition {pair}')
            pairs.add(pair)
            if t['event'] not in event_names: errors.append(f'{rel}: transition event not in EventCatalog: {t["event"]}')
    if k=='UseCase':
        for ref in s.get('requirementRefs',[]):
            n=ref.split('/')[-1].split('@')[0]
            if n not in names['Requirement']:errors.append(f'{rel}: missing requirement {ref}')
    if k=='Scenario':
        ref=s.get('useCaseRef','');n=ref.split('/')[-1].split('@')[0]
        if n and n not in names['UseCase']:errors.append(f'{rel}: missing use case {ref}')
        for event in s.get('expectedEvents',[]):
            if event not in event_names: errors.append(f'{rel}: expected event not in EventCatalog: {event}')
    if k=='ModelProfile' and d['metadata']['status']=='active':
        art=s.get('artifact',{})
        if not art.get('sha256') or not art.get('signature') or not art.get('sizeBytes'): errors.append(f'{rel}: active model missing release artifact evidence')
    if k=='TokenPolicy' and s.get('claimEnabled') and d['metadata']['status']=='active':
        errors.append(f'{rel}: claim-enabled token policy cannot be active in baseline')
print(json.dumps({'documents':len(docs),'kinds':len(names),'errors':len(errors)},indent=2))
if errors:
    print('\n'.join(errors[:500]));sys.exit(1)
