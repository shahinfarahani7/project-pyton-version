from pathlib import Path
root=Path(__file__).resolve().parents[1]
files=[p for p in root.rglob('*') if p.is_file()]
lines=0
for p in files:
 try:
  with p.open(encoding='utf-8') as f: lines+=sum(1 for _ in f)
 except Exception: pass
print({'files':len(files),'text_lines':lines,'bytes':sum(p.stat().st_size for p in files)})
