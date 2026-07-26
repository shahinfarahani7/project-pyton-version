#!/usr/bin/env python3
"""Validate canonical alignment for one OpenAPI/OperationContract/sample execution unit."""
from __future__ import annotations
import argparse,json
from pathlib import Path
import yaml
from schema_utils import operation_index

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(); p.add_argument('operation_id'); args=p.parse_args()
units=json.loads((ROOT/'cursor/execution-units.json').read_text())['units']
unit=next((x for x in units if x['operationId']==args.operation_id),None)
if not unit: raise SystemExit(f'UNKNOWN_OPERATION:{args.operation_id}')
doc=yaml.safe_load((ROOT/'contracts/openapi'/f"{unit['api']}.yaml").read_text())
method,path,operation=operation_index(doc)[args.operation_id]
contract=yaml.safe_load((ROOT/unit['contract']).read_text())['spec']
sample=json.loads((ROOT/unit['sample']).read_text())
errors=[]
if method!=unit['method'] or path!=unit['path']: errors.append('execution unit method/path mismatch')
if contract['method']!=method or contract['path']!=path: errors.append('operation contract method/path mismatch')
if set(contract.get('permissions',[]))!=set(operation.get('x-required-permissions',[])): errors.append('permission mismatch')
if sample['request']['method']!=method or sample['request']['path']!=path: errors.append('sample method/path mismatch')
if set(sample['expected']['requiredPermissions'])!=set(operation.get('x-required-permissions',[])): errors.append('sample permission mismatch')
if str(sample['expected']['successStatus']) not in {str(x) for x in contract.get('responseStatuses',[])}: errors.append('sample status not in OperationContract')
result={'status':'passed' if not errors else 'failed','operationId':args.operation_id,'service':unit['service'],'errors':errors}
print(json.dumps(result,indent=2)); raise SystemExit(0 if not errors else 1)
