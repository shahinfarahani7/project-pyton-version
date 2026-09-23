import json
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

path = r"C:\Users\Admin\.cursor\projects\d-shakhsi-Edgemint-project-pyton-version\agent-transcripts\56d3f21c-1af6-4277-9fc6-36a38c85b51b\56d3f21c-1af6-4277-9fc6-36a38c85b51b.jsonl"

for line_no in (4628, 4795):
    text = json.loads(open(path, encoding="utf-8").readlines()[line_no - 1])[
        "message"
    ]["content"][0]["text"]
    print(f"=== LINE {line_no} len={len(text)} ===")
    for kw in [
        "03494f44",
        "100 word",
        "Exactly 4",
        "Summarize this customer",
        "Preserve relevant",
        "inputText BEGIN",
        "066ad752",
        "13769",
        "options.summarize",
        "maxSummaryWords",
        "keyPointCount",
    ]:
        if kw.lower() in text.lower():
            idx = text.lower().find(kw.lower())
            snippet = text[max(0, idx - 40) : idx + 220].replace("\n", " ")
            print(f"  {kw}: {snippet[:240]}")

    m = re.search(
        r"Summarize this customer case.{0,1200}",
        text,
        re.S,
    )
    if m:
        cleaned = m.group(0).replace("I/flutter (11596): ", "")
        print("INSTRUCTIONS BLOCK:")
        print(cleaned[:1200])
    print()
