#!/usr/bin/env python3
from pathlib import Path
import yaml,json,hashlib
ROOT=Path(__file__).resolve().parents[1];out=[]
for p in sorted((ROOT/'dsl').rglob('*.yaml')):
 if 'schemas' in p.parts:continue
 d=yaml.safe_load(p.read_text());
 if isinstance(d,dict) and d.get('kind'):
  canonical=json.dumps(d,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
  out.append({'path':str(p.relative_to(ROOT)),'kind':d['kind'],'name':d['metadata']['name'],'version':d['metadata']['version'],'sha256':hashlib.sha256(canonical).hexdigest(),'document':d})
(ROOT/'build/canonical').mkdir(parents=True,exist_ok=True)
(ROOT/'build/canonical/index.json').write_text(json.dumps(out,sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n')
print(f'compiled {len(out)} documents')
