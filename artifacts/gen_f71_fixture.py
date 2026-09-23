import hashlib
from pathlib import Path

log_path = Path(
    r"C:\Users\Admin\.cursor\projects\d-shakhsi-Edgemint-project-pyton-version\attachments\56d3f21c-1af6-4277-9fc6-36a38c85b51b\Pasted_text_20260922-082720_.txt"
)
part1 = part2 = None
for line in log_path.read_text(encoding="utf-8").splitlines():
    if "[INFERENCE RESPONSE map PART 1/2]" in line:
        part1 = line.split("[INFERENCE RESPONSE map PART 1/2] ", 1)[1]
    if "[INFERENCE RESPONSE map PART 2/2]" in line:
        part2 = line.split("[INFERENCE RESPONSE map PART 2/2] ", 1)[1]

raw = part1 + part2
sha = hashlib.sha256(raw.encode()).hexdigest()

chunks = []
for index in range(0, len(raw), 180):
    chunk = raw[index : index + 180]
    chunk = chunk.replace("\\", "\\\\").replace("'", "\\'")
    chunks.append(f"    '{chunk}'")

lines = [
    "/// Map-stage model output for task `tsk_dev_f71a56dd` (log 20260922-082720).",
    "///",
    "/// Extracted from [INFERENCE RESPONSE map] PART 1/2 + PART 2/2. Log prefixes",
    "/// removed. The payload uses literal `\\n` and `\\\"` characters (zero real",
    "/// newlines) — model output, not Flutter log escaping.",
    "///",
    f"/// Log metadata: chars={len(raw)}, utf8Bytes={len(raw.encode())},",
    f"/// sha256={sha}, stopReason=model_eos, truncated=false.",
    f"const taskF71a56ddLogChars = {len(raw)};",
    f"const taskF71a56ddLogUtf8Bytes = {len(raw.encode())};",
    "const taskF71a56ddLogSha256 =",
    f"    '{sha}';",
    "",
    "const taskF71a56ddMapResponseRaw =",
    *chunks,
    ";",
    "",
]

out = Path(
    r"D:\shakhsi\Edgemint\project-pyton-version\src\apps\worker\test\inference\llm\fixtures\task_f71a56dd_map_response.dart"
)
out.write_text("\n".join(lines), encoding="utf-8")
print(f"wrote {out} len={len(raw)} sha={sha}")
