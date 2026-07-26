#!/usr/bin/env python3
"""Validate that Cursor has a complete, executable and non-ambiguous implementation plan."""
from __future__ import annotations
import json,re,shlex
from pathlib import Path
import yaml

ROOT=Path(__file__).resolve().parents[1]
errors=[]
work=json.loads((ROOT/'cursor/work-packages.json').read_text())['workPackages']
ids={w['id'] for w in work}
if len(work)!=len(ids): errors.append('duplicate work package ID')
for w in work:
    for key in ['objective','allowedPaths','requiredOutputs','acceptanceCriteria','verificationCommands','evidencePath','stopConditions','requiredExternalInputs','executionContract']:
        if key not in w or w[key] in (None,''): errors.append(f'{w.get("id")}:missing {key}')
    for dep in w.get('dependencies',[]):
        if dep not in ids: errors.append(f'{w["id"]}:unknown dependency:{dep}')
    legacy_tokens = ('global.json', 'Directory.Packages.props', '.csproj', '.sln', 'dotnet', 'sql server', 'mssql')
    serialized = json.dumps(w).lower()
    for token in legacy_tokens:
        if token.lower() in serialized:
            errors.append(f'{w["id"]}:legacy stack reference:{token}')
    for cmd in w.get('verificationCommands',[]):
        try:
            tokens=shlex.split(cmd)
        except ValueError as exc:
            errors.append(f'{w["id"]}:invalid verification command quoting:{exc}')
            tokens=[]
        if tokens and tokens[0] in {'python','python3','bash'}:
            rel=None
            if tokens[0] in {'python','python3'} and len(tokens)>1 and tokens[1]=='-m':
                rel=None  # module execution; importability is verified by the command itself
            elif len(tokens)>1:
                rel=tokens[1]
            if rel and (rel.endswith(('.py','.sh')) or rel.startswith(('tools/','tests/','src/'))):
                target=ROOT/rel
                if not target.exists() and rel not in w.get('requiredOutputs',[]):
                    errors.append(f'{w["id"]}:command target neither exists nor is required output:{rel}')
        for rel in re.findall(r'(src/[^\s]+\.py|tests/[^\s]+\.py)',cmd):
            target=ROOT/rel
            if not target.exists() and rel not in w.get('requiredOutputs',[]): errors.append(f'{w["id"]}:verification target neither exists nor is required output:{rel}')
# DAG cycle.
graph={w['id']:w.get('dependencies',[]) for w in work}; visiting=set(); visited=set()
def visit(node):
    if node in visiting: errors.append(f'cycle:{node}'); return
    if node in visited:return
    visiting.add(node)
    for dep in graph[node]: visit(dep)
    visiting.remove(node); visited.add(node)
for node in graph: visit(node)
# Operation unit coverage.
units_doc=json.loads((ROOT/'cursor/execution-units.json').read_text()); units=units_doc['units']
unit_ops=[u['operationId'] for u in units]
openapi_ops=[]
for p in (ROOT/'contracts/openapi').glob('*.yaml'):
    d=yaml.safe_load(p.read_text())
    for item in d.get('paths',{}).values():
        for method,op in item.items():
            if method in {'get','post','put','patch','delete'} and isinstance(op,dict) and op.get('operationId'): openapi_ops.append(op['operationId'])
if len(unit_ops)!=len(set(unit_ops)): errors.append('duplicate execution-unit operation')
if set(unit_ops)!=set(openapi_ops): errors.append(f'execution-unit coverage mismatch missing={sorted(set(openapi_ops)-set(unit_ops))} extra={sorted(set(unit_ops)-set(openapi_ops))}')
for u in units:
    for key in ['implementationTarget','testTarget','contract','sample','transaction','acceptanceCriteria','verificationCommands','workPackage']:
        if not u.get(key): errors.append(f'{u.get("operationId")}:missing {key}')
    if u['workPackage'] not in ids: errors.append(f'{u["operationId"]}:unknown work package')
    for rel in [u['contract'],u['sample']]:
        if not (ROOT/rel).exists(): errors.append(f'{u["operationId"]}:missing source:{rel}')
result={'status':'passed' if not errors else 'failed','workPackages':len(work),'executionUnits':len(units),'errors':errors}
print(json.dumps(result,indent=2))
raise SystemExit(0 if not errors else 1)
