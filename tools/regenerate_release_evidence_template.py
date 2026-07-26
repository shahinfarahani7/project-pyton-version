#!/usr/bin/env python3
"""Generate the complete schema-valid but intentionally unusable release-evidence example."""
from __future__ import annotations
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sets=json.loads((ROOT/'evidence/required-release-sets.json').read_text(encoding='utf-8'))
release_id='EM-20000101-EXAMPLE'; commit='0'*40
generated='2000-01-01T00:00:00Z'; expires='2000-01-01T01:00:00Z'; sha='0'*64

def ref(path:str)->dict:
    return {'path':path,'sha256':sha,'mediaType':'application/json','generatedAt':generated,'releaseId':release_id,'commitSha':commit}

template={
 'schemaVersion':'5.0','releaseId':release_id,'environment':'production','commitSha':commit,'generatedAt':generated,'expiresAt':expires,
 'trustedRoots':ref('evidence/actual/example/trusted-roots.json'),'repositoryState':ref('evidence/actual/example/repository-state.json'),
 'externalInputs':[{'name':n,'verifiedAt':generated,'evidence':ref(f'evidence/actual/example/external-inputs/{n}.json')} for n in sets['externalInputs']],
 'artifacts':[{'name':n,'digest':'sha256:'+sha,'producedAt':generated,'sbom':ref(f'evidence/actual/example/artifacts/{n}/sbom.json'),'signatureVerification':ref(f'evidence/actual/example/artifacts/{n}/signature-verification.json'),'provenance':ref(f'evidence/actual/example/artifacts/{n}/provenance.json'),'vulnerabilityReport':ref(f'evidence/actual/example/artifacts/{n}/vulnerability-report.json')} for n in sets['artifacts']],
 'tests':[{'name':n,'status':'passed','startedAt':generated,'completedAt':generated,'report':ref(f'evidence/actual/example/tests/{n}.json')} for n in sets['tests']],
 'approvals':[{'function':n,'approverId':'EXAMPLE-APPROVER','signingKeyId':'EXAMPLE-KEY','approvedAt':generated,'releaseId':release_id,'commitSha':commit,'signatureVerification':ref(f'evidence/actual/example/approvals/{n}.json')} for n in sets['approvals']],
 'canary':[{'stage':n,'status':'passed','startedAt':generated,'completedAt':generated,'report':ref(f'evidence/actual/example/canary/{n}-report.json'),'metrics':ref(f'evidence/actual/example/canary/{n}-metrics.json'),'rollbackReady':True} for n in sets['canary']],
}
(ROOT/'evidence/templates/release-evidence.example.json').write_text(json.dumps(template,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':'regenerated','externalInputs':len(template['externalInputs']),'artifacts':len(template['artifacts']),'tests':len(template['tests'])},indent=2))
