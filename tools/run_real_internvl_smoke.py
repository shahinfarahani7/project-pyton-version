#!/usr/bin/env python3
"""Run one real image+text inference with InternVL3 LiteRT-LM."""
import argparse, hashlib, json, time
from pathlib import Path
from litert_lm import Backend, Content, Contents, Engine, SamplerConfig, ThinkingConfig

def main() -> int:
    p = argparse.ArgumentParser(); p.add_argument("model"); p.add_argument("image"); p.add_argument("--repair-model"); p.add_argument("--report", default="artifacts/real-internvl-smoke.json"); a = p.parse_args()
    started = time.time()
    Path("/tmp/edgemint-internvl-cache").mkdir(parents=True, exist_ok=True)
    engine = Engine(a.model, backend=Backend.CPU(thread_count=4), vision_backend=Backend.CPU(thread_count=4), max_num_tokens=2048, max_num_images=1, cache_dir="/tmp/edgemint-internvl-cache")
    prompt = 'Inspect the image and identify the main product. Output one compact JSON object only. Required keys: label (specific product name), confidence (number from 0 to 1), evidence (array of short visible facts). Do not copy these instructions into values.'
    with engine.create_conversation(thinking_config=ThinkingConfig(False, 0), sampler_config=SamplerConfig(top_k=1, temperature=0.0, seed=42), max_output_tokens=256) as conv:
        response = conv.send_message(Contents.of(Content.ImageFile(str(Path(a.image).resolve())), prompt), thinking_config=ThinkingConfig(False, 0), max_output_tokens=256)
    raw = ''.join(x.get('text','') for x in response.get('content',[]) if isinstance(x,dict))
    raw = raw.split('</think>')[-1]
    direct_json = True
    try:
        data = json.loads(raw[raw.find('{'):raw.rfind('}')+1])
    except Exception:
        direct_json = False
        if not a.repair_model:
            print(json.dumps({'raw': raw})); raise
        repair_engine = Engine(a.repair_model, backend=Backend.CPU(thread_count=4), max_num_tokens=2048, cache_dir="/tmp/edgemint-qwen-cache")
        repair_prompt = f'Repair this malformed JSON. Return exactly one JSON object with label:string, confidence:number, evidence:array and no commentary: {raw}. /no_think'
        with repair_engine.create_conversation(thinking_config=ThinkingConfig(False,0), sampler_config=SamplerConfig(top_k=1,temperature=0.0,seed=42), max_output_tokens=256) as repair:
            fixed = repair.send_message(repair_prompt, thinking_config=ThinkingConfig(False,0), max_output_tokens=256)
        fixed_raw=''.join(x.get('text','') for x in fixed.get('content',[]) if isinstance(x,dict)).split('</think>')[-1]
        data=json.loads(fixed_raw[fixed_raw.find('{'):fixed_raw.rfind('}')+1])
    placeholders={'short label','specific product name','label'}
    passed = isinstance(data.get('label'),str) and data['label'].lower() not in placeholders and isinstance(data.get('confidence'),(int,float)) and 0 <= data['confidence'] <= 1 and isinstance(data.get('evidence'),list) and bool(data['evidence']) and all('short visible evidence' not in str(x).lower() for x in data['evidence'])
    report = {'passed': passed, 'runtime': 'litert-lm-python', 'model': Path(a.model).name, 'modelSha256': hashlib.sha256(Path(a.model).read_bytes()).hexdigest(), 'image': Path(a.image).name, 'directJson': direct_json, 'qwenRepairUsed': not direct_json, 'durationMs': round((time.time()-started)*1000), 'output': data}
    path=Path(a.report); path.parent.mkdir(parents=True,exist_ok=True); path.write_text(json.dumps(report,indent=2)+'\n'); print(json.dumps(report)); return 0 if passed else 1
if __name__ == '__main__': raise SystemExit(main())
