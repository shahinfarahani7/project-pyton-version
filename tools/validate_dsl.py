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
    if k=='UserResourcePolicy':
        rp=s['resourcePolicy']; modes=s['contributionModes']
        if rp['defaultApprovedPercent']>rp['maximumApprovedPercent']: errors.append(f'{rel}: defaultApprovedPercent exceeds maximumApprovedPercent')
        approved={m['approvedPercent'] for m in modes}
        if rp['defaultApprovedPercent'] not in approved: errors.append(f'{rel}: defaultApprovedPercent missing from contributionModes')
        if rp['maximumApprovedPercent'] not in approved: errors.append(f'{rel}: maximumApprovedPercent missing from contributionModes')
        ids=[m['id'] for m in modes]
        if len(set(ids))!=len(ids): errors.append(f'{rel}: duplicate contribution mode ids')
        default_modes=[m for m in modes if m['approvedPercent']==rp['defaultApprovedPercent']]
        if len(default_modes)!=1 or default_modes[0].get('requiresExplicitOptIn'): errors.append(f'{rel}: default mode must exist without explicit opt-in')
        max_modes=[m for m in modes if m['approvedPercent']==rp['maximumApprovedPercent']]
        if len(max_modes)!=1 or not max_modes[0].get('requiresExplicitOptIn'): errors.append(f'{rel}: maximum mode must require explicit opt-in')
    if k=='RuntimeCompatibilityProfile':
        recommended=set(s['recommendedRuntimeClasses'])
        class_ids={rc['id'] for rc in s['runtimeClasses']}
        if recommended!=class_ids: errors.append(f'{rel}: runtimeClasses ids must match recommendedRuntimeClasses')
        if len(class_ids)!=len(s['runtimeClasses']): errors.append(f'{rel}: duplicate runtime class ids')
        req_ids={tr['taskRuntimeClass'] for tr in s['taskRequirements']}
        if recommended!=req_ids: errors.append(f'{rel}: taskRequirements must cover all recommended runtime classes')
        pairs=set()
        for rule in s['coRunRules']:
            a,b=rule['runtimeA'],rule['runtimeB']
            if a not in class_ids or b not in class_ids: errors.append(f'{rel}: coRunRule references unknown runtime class')
            if a==b: errors.append(f'{rel}: coRunRule runtimeA and runtimeB must differ')
            key=tuple(sorted((a,b)))
            if key in pairs: errors.append(f'{rel}: duplicate coRunRule pair {key}')
            pairs.add(key)
            for req in s['taskRequirements']:
                for worker_class in req['requiredWorkerRuntimeClasses']:
                    if worker_class not in class_ids: errors.append(f'{rel}: taskRequirement references unknown runtime class {worker_class}')
    if k=='ExclusiveGroupPolicy':
        group_ids={g['id'] for g in s['groups']}
        if len(group_ids)!=len(s['groups']): errors.append(f'{rel}: duplicate exclusive group ids')
        light=set(s['lightWorkGroups'])
        if not light.issubset(group_ids): errors.append(f'{rel}: lightWorkGroups must reference defined groups')
        pairs=set()
        for rule in s['crossGroupRules']:
            a,b=rule['groupA'],rule['groupB']
            if a not in group_ids or b not in group_ids: errors.append(f'{rel}: crossGroupRule references unknown group')
            if a==b: errors.append(f'{rel}: crossGroupRule groupA and groupB must differ')
            key=tuple(sorted((a,b)))
            if key in pairs: errors.append(f'{rel}: duplicate crossGroupRule pair {key}')
            pairs.add(key)
        llm_ocr=[rule for rule in s['crossGroupRules'] if {rule['groupA'],rule['groupB']}=={'llm_inference','ocr_inference'}]
        if len(llm_ocr)!=1 or llm_ocr[0].get('concurrentAllowed') is not False:
            errors.append(f'{rel}: llm_inference + ocr_inference must disallow concurrent reservations by default')
    if k=='RetryPolicyMatrix':
        import json as _json
        catalog_path=ROOT/'src/shared/task-types/catalog.json'
        catalog_types=set()
        flex_violations: list[str] = []
        if catalog_path.exists():
            try:
                from edgemint.tasks.catalog_reconciliation import list_flex_dispatch_violations

                flex_violations = list_flex_dispatch_violations()
            except Exception:
                flex_non_executable=set()
                catalog=_json.loads(catalog_path.read_text(encoding='utf-8'))
                for category in catalog['categories']:
                    for item in category['types']:
                        catalog_types.add(str(item['value']))
                        if str(item.get('inputMode'))=='flex' and item.get('executable') is not False:
                            flex_non_executable.add(str(item['value']))
                for tt in flex_non_executable:
                    errors.append(f'{rel}: flex task {tt} must remain non-executable')
        else:
            flex_violations = []
        if flex_violations:
            for violation in flex_violations:
                errors.append(f'{rel}: flex dispatch gate violation: {violation}')
        if catalog_path.exists() and not flex_violations:
            catalog=_json.loads(catalog_path.read_text(encoding='utf-8'))
            for category in catalog['categories']:
                for item in category['types']:
                    catalog_types.add(str(item['value']))
        matrix_types=set()
        for row in s.get('entries',[]):
            tt=str(row['taskType'])
            if tt in matrix_types: errors.append(f'{rel}: duplicate taskType {tt}')
            matrix_types.add(tt)
            if not row.get('executable') and row.get('retryClass')!='no_retry':
                errors.append(f'{rel}: non-executable task {tt} must use retryClass no_retry')
        if catalog_types and matrix_types!=catalog_types:
            missing=sorted(catalog_types-matrix_types)
            extra=sorted(matrix_types-catalog_types)
            if missing: errors.append(f'{rel}: missing catalog task types: {", ".join(missing[:5])}')
            if extra: errors.append(f'{rel}: unknown task types: {", ".join(extra[:5])}')
    if k=='CheckpointPolicyMatrix':
        import json as _json
        catalog_path=ROOT/'src/shared/task-types/catalog.json'
        catalog_types=set()
        if catalog_path.exists():
            catalog=_json.loads(catalog_path.read_text(encoding='utf-8'))
            for category in catalog['categories']:
                for item in category['types']:
                    catalog_types.add(str(item['value']))
        matrix_types=set()
        for row in s.get('entries',[]):
            tt=str(row['taskType'])
            if tt in matrix_types: errors.append(f'{rel}: duplicate taskType {tt}')
            matrix_types.add(tt)
            if row.get('checkpointEnabled') and row.get('checkpointStrategy')=='none':
                errors.append(f'{rel}: enabled task {tt} must not use strategy none')
            if not row.get('checkpointEnabled') and row.get('checkpointStrategy')!='none':
                errors.append(f'{rel}: disabled task {tt} must use strategy none')
        if catalog_types and matrix_types!=catalog_types:
            missing=sorted(catalog_types-matrix_types)
            extra=sorted(matrix_types-catalog_types)
            if missing: errors.append(f'{rel}: missing catalog task types: {", ".join(missing[:5])}')
            if extra: errors.append(f'{rel}: unknown task types: {", ".join(extra[:5])}')
active_exclusive_groups=set()
for p,d in docs:
    if d['kind']=='ExclusiveGroupPolicy' and d['metadata'].get('status')=='active':
        active_exclusive_groups={g['id'] for g in d['spec']['groups']}
for p,d in docs:
    if d['kind']=='TaskResourceEnvelope' and active_exclusive_groups:
        eg=d['spec'].get('exclusiveGroup')
        if eg and eg not in active_exclusive_groups:
            errors.append(f'{p.relative_to(ROOT)}: exclusiveGroup {eg} missing from active ExclusiveGroupPolicy')
if errors:
    print('\n'.join(errors[:500]));sys.exit(1)
