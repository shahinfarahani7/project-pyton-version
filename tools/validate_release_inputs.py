#!/usr/bin/env python3
from pathlib import Path
import json,sys,yaml
ROOT=Path(__file__).resolve().parents[1];errors=[]
doc=yaml.safe_load((ROOT/'production/RELEASE-INPUTS.yaml').read_text())
if doc.get('metadata',{}).get('version')!='5.0.0':errors.append('release input version mismatch')
items=[x for group in doc.get('spec',{}).values() if isinstance(group,list) for x in group];by={x.get('name'):x for x in items}
expected={'POSTGRES_ENGINE':('const','postgres'),'POSTGRES_ENGINE_VERSION':('const','18.4'),'POSTGRES_PARAMETER_GROUP_FAMILY':('const','postgres18')}
for name,(key,value) in expected.items():
 if by.get(name,{}).get(key)!=value:errors.append(f'{name} mismatch')
for name in ['PYTHON_RUNTIME_IMAGE','POSTGRES_DEV_IMAGE','POSTGRES_TOOLS_IMAGE','MINIO_IMAGE','MAILPIT_IMAGE']:
 item=by.get(name)
 if not item:errors.append('missing immutable image release input:'+name)
 elif '@sha256:' not in item.get('format',''):errors.append('image input does not require digest:'+name)
text='\n'.join(p.read_text(errors='ignore') for p in [ROOT/'production/RELEASE-INPUTS.yaml',ROOT/'compose.yaml',*ROOT.glob('src/backend/services/*/Dockerfile')])
if ':latest' in text:errors.append('mutable latest image token remains')
print(json.dumps({'status':'passed' if not errors else 'failed','releaseInputs':len(items),'errors':errors},indent=2));sys.exit(1 if errors else 0)
