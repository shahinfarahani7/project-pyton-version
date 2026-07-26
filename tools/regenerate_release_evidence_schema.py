#!/usr/bin/env python3
"""Regenerate the release evidence schema from canonical release inputs and required sets."""
from __future__ import annotations
import json
from pathlib import Path
import yaml

ROOT=Path(__file__).resolve().parents[1]
sets_path=ROOT/'evidence/required-release-sets.json'
sets=json.loads(sets_path.read_text(encoding='utf-8'))
release_inputs=yaml.safe_load((ROOT/'production/RELEASE-INPUTS.yaml').read_text(encoding='utf-8'))['spec']
external=[]
for items in release_inputs.values():
    for item in items:
        if item['name']!='RELEASE_APPROVAL_MANIFEST': external.append(item['name'])
sets['externalInputs']=sorted(set(external))
sets_path.write_text(json.dumps(sets,indent=2)+'\n',encoding='utf-8')
release_id={'type':'string','pattern':'^EM-[0-9]{8}-[A-Z0-9]{6,20}$'}
commit={'type':'string','pattern':'^[a-f0-9]{40}$'}
ref={'type':'object','additionalProperties':False,'required':['path','sha256','mediaType','generatedAt','releaseId','commitSha'],'properties':{
 'path':{'type':'string','pattern':'^evidence/actual/[A-Za-z0-9._/-]+$'},'sha256':{'type':'string','pattern':'^[a-f0-9]{64}$'},
 'mediaType':{'type':'string','minLength':3},'generatedAt':{'type':'string','format':'date-time'},'releaseId':release_id,'commitSha':commit}}
def fixed_array(names,item): return {'type':'array','minItems':len(names),'maxItems':len(names),'items':item}
schema={'$schema':'https://json-schema.org/draft/2020-12/schema','$id':'https://schemas.edgemint.io/release-evidence-v5.0.json','type':'object','additionalProperties':False,
'required':['schemaVersion','releaseId','environment','commitSha','generatedAt','expiresAt','trustedRoots','repositoryState','artifacts','tests','approvals','externalInputs','canary'],
'properties':{
 'schemaVersion':{'const':'5.0'},'releaseId':release_id,'environment':{'const':'production'},'commitSha':commit,
 'generatedAt':{'type':'string','format':'date-time'},'expiresAt':{'type':'string','format':'date-time'},'trustedRoots':{'$ref':'#/$defs/evidenceRef'},'repositoryState':{'$ref':'#/$defs/evidenceRef'},
 'externalInputs':fixed_array(sets['externalInputs'],{'type':'object','additionalProperties':False,'required':['name','verifiedAt','evidence'],'properties':{'name':{'enum':sets['externalInputs']},'verifiedAt':{'type':'string','format':'date-time'},'evidence':{'$ref':'#/$defs/evidenceRef'}}}),
 'artifacts':fixed_array(sets['artifacts'],{'type':'object','additionalProperties':False,'required':['name','digest','producedAt','sbom','signatureVerification','provenance','vulnerabilityReport'],'properties':{
  'name':{'enum':sets['artifacts']},'digest':{'type':'string','pattern':'^sha256:[a-f0-9]{64}$'},'producedAt':{'type':'string','format':'date-time'},
  'sbom':{'$ref':'#/$defs/evidenceRef'},'signatureVerification':{'$ref':'#/$defs/evidenceRef'},'provenance':{'$ref':'#/$defs/evidenceRef'},'vulnerabilityReport':{'$ref':'#/$defs/evidenceRef'}}}),
 'tests':fixed_array(sets['tests'],{'type':'object','additionalProperties':False,'required':['name','status','startedAt','completedAt','report'],'properties':{
  'name':{'enum':sets['tests']},'status':{'const':'passed'},'startedAt':{'type':'string','format':'date-time'},'completedAt':{'type':'string','format':'date-time'},'report':{'$ref':'#/$defs/evidenceRef'}}}),
 'approvals':fixed_array(sets['approvals'],{'type':'object','additionalProperties':False,'required':['function','approverId','signingKeyId','approvedAt','releaseId','commitSha','signatureVerification'],'properties':{
  'function':{'enum':sets['approvals']},'approverId':{'type':'string','minLength':3},'signingKeyId':{'type':'string','minLength':3},'approvedAt':{'type':'string','format':'date-time'},
  'releaseId':release_id,'commitSha':commit,'signatureVerification':{'$ref':'#/$defs/evidenceRef'}}}),
 'canary':fixed_array(sets['canary'],{'type':'object','additionalProperties':False,'required':['stage','status','startedAt','completedAt','report','metrics','rollbackReady'],'properties':{
  'stage':{'enum':sets['canary']},'status':{'const':'passed'},'startedAt':{'type':'string','format':'date-time'},'completedAt':{'type':'string','format':'date-time'},
  'report':{'$ref':'#/$defs/evidenceRef'},'metrics':{'$ref':'#/$defs/evidenceRef'},'rollbackReady':{'const':True}}})},
'$defs':{'evidenceRef':ref}}
(ROOT/'evidence/schemas/release-evidence.schema.json').write_text(json.dumps(schema,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':'regenerated','externalInputs':len(sets['externalInputs']),'artifacts':len(sets['artifacts']),'tests':len(sets['tests'])},indent=2))
