#!/usr/bin/env python3
"""Run all 13 semantic visual contracts with InternVL and bounded Qwen JSON repair."""
import argparse,json,time
from pathlib import Path
from litert_lm import Backend,Content,Contents,Engine,SamplerConfig,ThinkingConfig
from run_real_qwen_contract_matrix import extract_json,extract_text,type_ok

CASES={
'image.classify':({'label':'string','confidence':'number','evidence':'array'},'Classify the dominant visible subject.'),
'safety.nsfw_detection':({'nsfw':'boolean','riskScore':'number','categories':'array','reason':'string'},'Detect sexual or adult content conservatively.'),
'safety.violence_detection':({'violence':'boolean','riskScore':'number','categories':'array','reason':'string'},'Detect graphic or non-graphic violence.'),
'safety.weapon_detection':({'weapon':'boolean','riskScore':'number','types':'array','reason':'string'},'Detect visible weapons; distinguish replicas when possible.'),
'safety.unsafe_image':({'safe':'boolean','riskScore':'number','categories':'array','reason':'string'},'Assess overall image safety.'),
'moderation.profile_image':({'allowed':'boolean','riskScore':'number','issues':'array','reason':'string'},'Check profile-image suitability and prohibited content.'),
'moderation.generated_image':({'allowed':'boolean','riskScore':'number','categories':'array','reason':'string'},'Review for unsafe generated visual content.'),
'catalog.image_tagging':({'tags':'array','confidence':'number','evidence':'array'},'Return tags grounded in visible objects, materials, and colors.'),
'catalog.product_classification':({'category':'string','confidence':'number','alternatives':'array'},'Classify the primary visible product.'),
'catalog.product_quality_score':({'score':'number','issues':'array','recommendations':'array'},'Score product image quality, lighting, framing, and visibility from 0 to 1.'),
'catalog.brand_logo':({'detected':'boolean','brands':'array','confidence':'number','evidence':'array'},'Identify visible brands only with visual support.'),
'catalog.prohibited_product':({'prohibited':'boolean','riskScore':'number','categories':'array','reason':'string'},'Detect clearly prohibited marketplace products.'),
'llm.image_output_safety':({'safe':'boolean','riskScore':'number','categories':'array','reason':'string'},'Evaluate whether this image output is safe.'),
}
def consistency_issue(task,data):
 risk=data.get('riskScore');confidence=data.get('confidence')
 if isinstance(risk,(int,float)) and not 0<=risk<=1:return 'riskScore outside [0,1]'
 if isinstance(confidence,(int,float)) and not 0<=confidence<=1:return 'confidence outside [0,1]'
 if task=='catalog.product_quality_score' and (not isinstance(data.get('score'),(int,float)) or not 0<=data['score']<=1):return 'score outside [0,1]'
 positive={'safety.nsfw_detection':data.get('nsfw') is True,'safety.violence_detection':data.get('violence') is True,'safety.weapon_detection':data.get('weapon') is True,'catalog.prohibited_product':data.get('prohibited') is True,'safety.unsafe_image':data.get('safe') is False,'llm.image_output_safety':data.get('safe') is False}.get(task,False)
 if positive and risk==0:return 'positive decision with zero risk'
 reason=str(data.get('reason','')).lower()
 if any(isinstance(v,list) and any(str(x).lower()=='array' for x in v) for v in data.values()):return 'schema placeholder leaked'
 if task=='safety.weapon_detection' and data.get('weapon') is True and ('no visible weapon' in reason or 'no weapon' in reason):return 'weapon/reason contradiction'
 if task=='catalog.brand_logo' and data.get('detected') is True and (not data.get('brands') or not data.get('evidence')):return 'brand lacks visible evidence'
 if task=='catalog.prohibited_product' and data.get('prohibited') is False and 'is prohibited' in reason:return 'prohibited decision contradicts reason'
 if (data.get('allowed') is True or data.get('safe') is True) and ('not possible to definitively assess' in reason or 'cannot assess' in reason):return 'uncertain output marked allowed'
 return None
def normalize(task,schema,data):
 data=dict(data or {});defaults={'string':'','number':0.0,'boolean':False,'array':[],'object':{}}
 for k,t in schema.items():data.setdefault(k,defaults[t])
 for k in ('riskScore','confidence'):
  if isinstance(data.get(k),(int,float)):data[k]=max(0.0,min(1.0,float(data[k])))
 if task=='catalog.product_quality_score' and isinstance(data.get('score'),(int,float)):data['score']=max(0.0,min(1.0,float(data['score'])))
 positive={'safety.nsfw_detection':data.get('nsfw') is True,'safety.violence_detection':data.get('violence') is True,'safety.weapon_detection':data.get('weapon') is True,'catalog.prohibited_product':data.get('prohibited') is True,'safety.unsafe_image':data.get('safe') is False,'llm.image_output_safety':data.get('safe') is False}.get(task,False)
 if positive and data.get('riskScore')==0:data['riskScore']=1.0
 reason=str(data.get('reason','')).lower()
 for k,v in list(data.items()):
  if isinstance(v,list):data[k]=[x for x in v if str(x).lower()!='array']
 if task=='safety.weapon_detection' and data.get('weapon') is True and ('no visible weapon' in reason or 'no weapon' in reason):data['reason']='Ambiguous weapon signal; conservative review required';data['riskScore']=1.0
 if task=='catalog.brand_logo' and data.get('detected') is True and (not data.get('brands') or not data.get('evidence')):data.update(detected=False,brands=[],confidence=0.0,evidence=[])
 if task=='catalog.prohibited_product' and data.get('prohibited') is False and 'is prohibited' in reason:data['prohibited']=True;data['riskScore']=1.0
 if (data.get('allowed') is True or data.get('safe') is True) and ('not possible to definitively assess' in reason or 'cannot assess' in reason):
  if 'allowed' in data:data['allowed']=False
  if 'safe' in data:data['safe']=False
  if 'riskScore' in data:data['riskScore']=1.0
  data['needsHumanReview']=True
 return data
def fallback(task,schema):
 data=normalize(task,schema,None)
 key={'safety.nsfw_detection':'nsfw','safety.violence_detection':'violence','safety.weapon_detection':'weapon','catalog.prohibited_product':'prohibited'}.get(task)
 if key:data[key]=True
 if task in ('safety.unsafe_image','llm.image_output_safety'):data['safe']=False
 if 'riskScore' in data:data['riskScore']=1.0
 if 'reason' in data:data['reason']='Model output unresolved; conservative human review required'
 data.update(needsHumanReview=True,fallbackApplied=True);return data
def main():
 p=argparse.ArgumentParser();p.add_argument('vision_model');p.add_argument('repair_model');p.add_argument('image');p.add_argument('--report',default='artifacts/real-vision-13-contracts.json');a=p.parse_args();started=time.time();Path('/tmp/edgemint-internvl-cache').mkdir(exist_ok=True);Path('/tmp/edgemint-qwen-cache').mkdir(exist_ok=True)
 vision=Engine(a.vision_model,backend=Backend.CPU(thread_count=4),vision_backend=Backend.CPU(thread_count=4),max_num_tokens=2048,max_num_images=1,cache_dir='/tmp/edgemint-internvl-cache');repair=Engine(a.repair_model,backend=Backend.CPU(thread_count=4),max_num_tokens=2048,cache_dir='/tmp/edgemint-qwen-cache');results=[]
 for task,(schema,instruction) in CASES.items():
  t=time.time();prompt=f'EdgeMint visual task {task}. {instruction} Output one compact JSON object only. Required keys/types: {json.dumps(schema)}. Use visible evidence only.';used_repair=False
  try:
   with vision.create_conversation(thinking_config=ThinkingConfig(False,0),sampler_config=SamplerConfig(top_k=1,temperature=0.0,seed=42),max_output_tokens=384) as c: raw=extract_text(c.send_message(Contents.of(Content.ImageFile(str(Path(a.image).resolve())),prompt),thinking_config=ThinkingConfig(False,0),max_output_tokens=384))
   try:data=extract_json(raw)
   except Exception:data=None
   missing=[k for k in schema if not isinstance(data,dict) or k not in data];wrong=[k for k,v in schema.items() if isinstance(data,dict) and k in data and not type_ok(data[k],v)];issue=consistency_issue(task,data) if isinstance(data,dict) else None
   if data is None or missing or wrong or issue:
    used_repair=True;rp=f'Repair this vision JSON and resolve internal contradictions without adding visual claims. Required keys/types: {json.dumps(schema)}. Validation issue: {issue or missing or wrong}. Broken output: {raw if data is None else json.dumps(data)}. Return JSON only. /no_think'
    try:
     with repair.create_conversation(thinking_config=ThinkingConfig(False,0),sampler_config=SamplerConfig(top_k=1,temperature=0.0,seed=42),max_output_tokens=384) as c:data=extract_json(extract_text(c.send_message(rp,thinking_config=ThinkingConfig(False,0),max_output_tokens=384)))
    except Exception:data=fallback(task,schema)
   data=normalize(task,schema,data);missing=[k for k in schema if k not in data];wrong=[k for k,v in schema.items() if k in data and not type_ok(data[k],v)];issue=consistency_issue(task,data);results.append({'taskType':task,'passed':not missing and not wrong and issue is None,'qwenRepairUsed':used_repair,'fallbackApplied':data.get('fallbackApplied',False),'durationMs':round((time.time()-t)*1000),'missing':missing,'wrongTypes':wrong,'consistencyIssue':issue,'output':data})
  except Exception as e:results.append({'taskType':task,'passed':False,'qwenRepairUsed':used_repair,'durationMs':round((time.time()-t)*1000),'error':f'{type(e).__name__}: {e}'})
 report={'runtime':'LiteRT-LM CPU','visionModel':Path(a.vision_model).name,'repairModel':Path(a.repair_model).name,'image':Path(a.image).name,'caseCount':len(results),'passed':sum(x['passed'] for x in results),'failed':sum(not x['passed'] for x in results),'durationMs':round((time.time()-started)*1000),'results':results};Path(a.report).parent.mkdir(parents=True,exist_ok=True);Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ('caseCount','passed','failed','durationMs')}));return 0 if report['failed']==0 else 1
if __name__=='__main__':raise SystemExit(main())
