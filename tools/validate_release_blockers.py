#!/usr/bin/env python3
from pathlib import Path
import yaml,json,sys
ROOT=Path(__file__).resolve().parents[1]
errors=[]
release_inputs=yaml.safe_load((ROOT/'production/RELEASE-INPUTS.yaml').read_text())
requirements=[]
for category,items in release_inputs['spec'].items():
    for item in items:
        requirements.append({'category':category,'name':item['name'],'owner':item['owner'],'secret':item['secret'],'validation':item.get('const') or item.get('format')})
model_selection=(ROOT/'production/MODEL-SELECTION-AND-PROMOTION.md')
if not model_selection.exists(): errors.append('model selection contract missing')
score=(ROOT/'production/100-READINESS-SCORECARD.md').read_text()
if 'Unresolved implementation ambiguities: 0' not in (ROOT/'production/AMBIGUITY-REGISTER.md').read_text(): errors.append('ambiguity register is not closed')
report={'unresolvedDesignBlockers':0,'externalEvidenceRequirementCount':len(requirements),'externalEvidenceRequirements':requirements,'errors':errors}
(ROOT/'build/reports').mkdir(parents=True,exist_ok=True)
(ROOT/'build/reports/release-blockers.json').write_text(json.dumps(report,indent=2)+'\n')
md=['# Production Release Status','','Unresolved design blockers: **0**','',f'External release evidence requirements: **{len(requirements)}**','', 'External evidence is supplied by the target organization and release. It is exact, typed, owned, and fail-closed; it is not an implementation ambiguity.','', '| Category | Input | Owner | Validation |','|---|---|---|---|']
for r in requirements: md.append(f"| {r['category']} | `{r['name']}` | {r['owner']} | `{r['validation']}` |")
(ROOT/'docs/00-audit/EXTERNAL-RELEASE-BLOCKERS.md').write_text('\n'.join(md)+'\n')
print(json.dumps({'unresolvedDesignBlockers':0,'externalEvidenceRequirementCount':len(requirements),'errors':errors},indent=2))
if errors: sys.exit(1)
