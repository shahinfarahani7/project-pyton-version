#!/usr/bin/env python3
"""Execute the production MediaPipe SelfieSegmenter TFLite artifact."""
import argparse, hashlib, json, time
from pathlib import Path
import numpy as np
from PIL import Image
from ai_edge_litert.interpreter import Interpreter

def main() -> int:
    p=argparse.ArgumentParser(); p.add_argument('model'); p.add_argument('image'); p.add_argument('--report',default='artifacts/real-segmentation-smoke.json'); p.add_argument('--output',default='artifacts/real-segmentation-output.png'); a=p.parse_args()
    started=time.time(); source=Image.open(a.image).convert('RGB'); resized=source.resize((256,256))
    tensor=np.asarray(resized,dtype=np.float32)[None,...]/255.0
    runtime=Interpreter(a.model); runtime.allocate_tensors(); inp=runtime.get_input_details()[0]; out=runtime.get_output_details()[0]
    runtime.set_tensor(inp['index'],tensor); infer=time.time(); runtime.invoke(); infer_ms=round((time.time()-infer)*1000)
    mask=runtime.get_tensor(out['index'])[0,:,:,0]; alpha=Image.fromarray(np.uint8(np.clip(mask,0,1)*255),'L').resize(source.size)
    rgba=source.convert('RGBA'); rgba.putalpha(alpha); out_path=Path(a.output); out_path.parent.mkdir(parents=True,exist_ok=True); rgba.save(out_path)
    report={'passed': bool(np.isfinite(mask).all() and mask.size==65536), 'runtime':'ai-edge-litert 2.2.0/XNNPACK CPU', 'model':Path(a.model).name, 'modelSha256':hashlib.sha256(Path(a.model).read_bytes()).hexdigest(), 'inputShape':list(tensor.shape), 'outputShape':list(mask.shape), 'maskMin':float(mask.min()), 'maskMax':float(mask.max()), 'maskMean':float(mask.mean()), 'inferenceMs':infer_ms, 'durationMs':round((time.time()-started)*1000), 'output':str(out_path)}
    report_path=Path(a.report); report_path.parent.mkdir(parents=True,exist_ok=True); report_path.write_text(json.dumps(report,indent=2)+'\n'); print(json.dumps(report)); return 0 if report['passed'] else 1
if __name__=='__main__': raise SystemExit(main())
