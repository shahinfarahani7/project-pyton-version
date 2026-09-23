import hashlib
import json
import re

path = r"C:\Users\Admin\.cursor\projects\d-shakhsi-Edgemint-project-pyton-version\attachments\56d3f21c-1af6-4277-9fc6-36a38c85b51b\Pasted_text_20260922-082720_.txt"
part1 = part2 = None
with open(path, encoding="utf-8") as f:
    for line in f:
        if "[INFERENCE RESPONSE map PART 1/2]" in line:
            part1 = line.split("[INFERENCE RESPONSE map PART 1/2] ", 1)[1].rstrip("\n")
        if "[INFERENCE RESPONSE map PART 2/2]" in line:
            part2 = line.split("[INFERENCE RESPONSE map PART 2/2] ", 1)[1].rstrip("\n")

raw = part1 + part2
assert len(raw) == 1362
assert hashlib.sha256(raw.encode()).hexdigest() == (
    "5cbc6bca1457e7737b52a3b69a3a94fe4e4e74fbe3e73685f3abb3a46cca39ff"
)


def strip_fences(inp: str) -> str:
    lines = inp.split("\n")
    if not inp.startswith("```"):
        return inp.strip()
    open_trim = lines[0].strip()
    body = []
    after = open_trim[3:].lstrip() if len(open_trim) > 3 else ""
    if after:
        body.append(after)
    for index in range(1, len(lines)):
        trimmed = lines[index].strip()
        if trimmed.startswith("```") and len(trimmed) >= 3:
            break
        body.append(lines[index])
    return "\n".join(body).rstrip()


def unescape_json_literals(text: str) -> str:
    out = []
    index = 0
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            nxt = text[index + 1]
            if nxt == "n":
                out.append("\n")
                index += 2
                continue
            if nxt == "r":
                out.append("\r")
                index += 2
                continue
            if nxt == "t":
                out.append("\t")
                index += 2
                continue
            if nxt == '"':
                out.append('"')
                index += 2
                continue
            if nxt == "\\":
                out.append("\\")
                index += 2
                continue
            if nxt == "/":
                out.append("/")
                index += 2
                continue
            if nxt == "u" and index + 5 < len(text):
                out.append(chr(int(text[index + 2 : index + 6], 16)))
                index += 6
                continue
        out.append(char)
        index += 1
    return "".join(out)


def extract_first_object(text: str) -> str | None:
    start = text.find("{")
    if start < 0:
        return None
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start : index + 1]
    return None


cleaned = strip_fences(raw)
print("cleaned starts:", repr(cleaned[:40]))
print("real newlines in cleaned:", cleaned.count("\n"))
print("literal \\n count:", cleaned.count("\\n"))
print("extract before unescape:", extract_first_object(cleaned))

unescaped = unescape_json_literals(cleaned)
obj = extract_first_object(unescaped)
print("extract after unescape:", obj is not None, "len", len(obj or ""))
parsed = json.loads(obj)
print("parsed keys:", list(parsed.keys()))
print("keyPoints:", len(parsed["keyPoints"]))
