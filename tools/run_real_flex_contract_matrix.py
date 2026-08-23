#!/usr/bin/env python3
"""Execute all nine specialized Flex contracts with real Qwen LiteRT-LM."""
import argparse, json, time
from pathlib import Path
from litert_lm import Backend, Engine, SamplerConfig, ThinkingConfig
from run_real_qwen_contract_matrix import extract_json, extract_text, type_ok

CASES = {
 'catalog.fake_listing': ({'fake':'boolean','riskScore':'number','reasons':'array'}, {'listing':{'title':'New phone 90% off','price':99,'sellerSignals':{'ageDays':1,'sales':0}}}),
 'llm.ai_tag_validation': ({'validTags':'array','rejectedTags':'array','score':'number','reasons':'array'}, {'content':'red leather shoulder bag','candidateTags':['red','leather','backpack']}),
 'llm.caption_validation': ({'valid':'boolean','score':'number','issues':'array','suggestedCaption':'string'}, {'caption':'blue shoe','imageDescription':'red leather bag'}),
 'dataset.label_verification': ({'valid':'boolean','correctedLabel':'string','confidence':'number','reasons':'array'}, {'record':{'text':'parcel late'},'candidateLabel':'billing','allowedLabels':['billing','delivery']}),
 'dataset.duplicate_cleanup': ({'duplicateGroups':'array','keepIds':'array','removeIds':'array'}, {'records':[{'id':'1','payload':'USB C cable 1m'},{'id':'2','payload':'1 metre USB-C cable'}]}),
 'dataset.low_quality_removal': ({'acceptedIds':'array','rejected':'array','threshold':'number'}, {'records':[{'id':'1','payload':'detailed description'},{'id':'2','payload':'x'}],'qualityCriteria':['specific','useful'],'threshold':0.6}),
 'ml.active_learning_prelabel': ({'label':'string','confidence':'number','needsHumanReview':'boolean','evidence':'array'}, {'record':{'text':'package arrived late'},'allowedLabels':['delivery','billing']}),
 'ml.consensus_label_validation': ({'consensusLabel':'string','agreementScore':'number','disputed':'boolean','reason':'string'}, {'record':{'text':'great'},'votes':[{'annotatorId':'a','label':'positive'},{'annotatorId':'b','label':'positive'},{'annotatorId':'c','label':'neutral'}]}),
 'ml.human_verification_quality': ({'valid':'boolean','qualityScore':'number','issues':'array','recommendation':'string'}, {'record':{'claim':'receipt visible'},'verification':{'verdict':'yes','evidence':['merchant and total visible']}}),
}

def main():
 p=argparse.ArgumentParser();p.add_argument('model');p.add_argument('--report',default='artifacts/real-flex-9-contracts.json');a=p.parse_args();started=time.time();Path('/tmp/edgemint-qwen-cache').mkdir(exist_ok=True)
 engine=Engine(a.model,backend=Backend.CPU(thread_count=4),max_num_tokens=2048,cache_dir='/tmp/edgemint-qwen-cache');results=[]
 for task,(schema,payload) in CASES.items():
  t=time.time();prompt=f'EdgeMint task {task}. Return exactly one JSON object. Required keys/types: {json.dumps(schema)}. Input: {json.dumps(payload)}. /no_think'
  try:
   with engine.create_conversation(thinking_config=ThinkingConfig(False,0),sampler_config=SamplerConfig(top_k=1,temperature=0.0,seed=42),max_output_tokens=256) as c: data=extract_json(extract_text(c.send_message(prompt,thinking_config=ThinkingConfig(False,0),max_output_tokens=256)))
   missing=[k for k in schema if k not in data];wrong=[k for k,v in schema.items() if k in data and not type_ok(data[k],v)];results.append({'taskType':task,'passed':not missing and not wrong,'durationMs':round((time.time()-t)*1000),'missing':missing,'wrongTypes':wrong,'output':data})
  except Exception as e: results.append({'taskType':task,'passed':False,'durationMs':round((time.time()-t)*1000),'error':f'{type(e).__name__}: {e}'})
 report={'runtime':'litert-lm-python','model':Path(a.model).name,'caseCount':len(results),'passed':sum(x['passed'] for x in results),'failed':sum(not x['passed'] for x in results),'durationMs':round((time.time()-started)*1000),'results':results};Path(a.report).parent.mkdir(parents=True,exist_ok=True);Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ('caseCount','passed','failed','durationMs')}));return 0 if report['failed']==0 else 1
if __name__=='__main__':raise SystemExit(main())
