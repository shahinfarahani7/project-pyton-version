import hashlib
import json
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

path = r"C:\Users\Admin\.cursor\projects\d-shakhsi-Edgemint-project-pyton-version\agent-transcripts\56d3f21c-1af6-4277-9fc6-36a38c85b51b\56d3f21c-1af6-4277-9fc6-36a38c85b51b.jsonl"
text = json.loads(open(path, encoding="utf-8").readlines()[4627])["message"]["content"][0]["text"]

expected_sha = "066ad7525cf932b844c1e6c90a8fd68bd73b0785c8dea92edb66351d450daba7"
expected_chars = 13769

parts = {}
for m in re.finditer(
    r"\[TASK SOURCE inputText PART (\d+)/(\d+)\] (.+?)(?=I/flutter \(11596\): \[EdgeMint\||$)",
    text,
    re.S,
):
    idx = int(m.group(1))
    total = int(m.group(2))
    body = m.group(3)
    body = re.sub(r"I/flutter \(11596\): ?", "", body)
    body = body.replace("\r\n", "\n")
    parts[idx] = body

print(f"parts found: {len(parts)} / expected total from first match")
if parts:
    print(f"total marker: {max(int(m.group(2)) for m in re.finditer(r'PART (\d+)/(\d+)', text))}")

ordered = [parts[i] for i in sorted(parts)]
reconstructed = "".join(ordered)
print(f"reconstructed chars={len(reconstructed)} utf8={len(reconstructed.encode('utf-8'))}")
sha = hashlib.sha256(reconstructed.encode("utf-8")).hexdigest()
print(f"sha256={sha}")
print(f"matches expected={sha == expected_sha}")
print(f"matches char count={len(reconstructed) == expected_chars}")
if reconstructed:
    print("head:", reconstructed[:120].replace("\n", "\\n"))
    print("tail:", reconstructed[-120:].replace("\n", "\\n"))
