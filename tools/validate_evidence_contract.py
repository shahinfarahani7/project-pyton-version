#!/usr/bin/env python3
"""Validate release-evidence schemas, examples, trust anchoring, and CI binding."""
from __future__ import annotations
import json,re,sys
from datetime import datetime,timezone
from pathlib import Path
from jsonschema import Draft202012Validator,FormatChecker

ROOT=Path(__file__).resolve().parents[1]; errors=[]
schema=json.loads((ROOT/'evidence/schemas/release-evidence.schema.json').read_text())
template=json.loads((ROOT/'evidence/templates/release-evidence.example.json').read_text())
for issue in Draft202012Validator(schema,format_checker=FormatChecker()).iter_errors(template):
    errors.append('template:'+('/'.join(map(str,issue.path)) or 'root')+':'+issue.message)
try:
    if datetime.fromisoformat(template['expiresAt'].replace('Z','+00:00'))>=datetime.now(timezone.utc): errors.append('example evidence must remain expired')
except Exception as exc: errors.append('example expiry invalid:'+str(exc))
sets=json.loads((ROOT/'evidence/required-release-sets.json').read_text())
for field,key in [('externalInputs','name'),('artifacts','name'),('tests','name'),('approvals','function'),('canary','stage')]:
    actual=[x[key] for x in template[field]]
    if actual!=sets[field]: errors.append(f'example set mismatch:{field}')
trust_schema=json.loads((ROOT/'evidence/schemas/trusted-roots.schema.json').read_text())
Draft202012Validator.check_schema(trust_schema)
gate=(ROOT/'tools/production_gate.py').read_text()
for token in ['PROTECTED_TRUSTED_KEY_SHA256_REQUIRED','TRUSTED_KEY_SHA256_MISMATCH','TRUSTED_ROOT_ATTESTATION_MISMATCH','trusted-roots.schema.json','COSIGN_TRUSTED_PUBLIC_KEY_SHA256']:
    if token not in gate: errors.append('production gate trust control missing:'+token)
workflow=(ROOT/'.github/workflows/release.yml').read_text()
for token in ['inputs.commit_sha','inputs.evidence_run_id','actions/download-artifact@v4','COSIGN_TRUSTED_PUBLIC_KEY_SHA256','--expected-trusted-key-sha256','git rev-parse HEAD']:
    if token not in workflow: errors.append('release workflow binding missing:'+token)
wp=json.loads((ROOT/'cursor/work-packages.json').read_text())
if '--expected-trusted-key-sha256' not in json.dumps(wp): errors.append('final work package lacks trusted-key digest binding')
lock=(ROOT/'tools/requirements.lock').read_text()
if lock.count('--hash=sha256:')<9: errors.append('Python dependency lock is not fully hash-pinned')
ci=(ROOT/'.github/workflows/ci.yml').read_text()
if 'pip install --require-hashes -r tools/requirements.lock' not in ci: errors.append('CI does not enforce Python dependency hashes')
print(json.dumps({'status':'passed' if not errors else 'failed','externalInputs':len(sets['externalInputs']),'artifacts':len(sets['artifacts']),'tests':len(sets['tests']),'errors':errors},indent=2));sys.exit(1 if errors else 0)
