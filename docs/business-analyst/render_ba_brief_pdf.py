"""Render BA brief Markdown to PDF via headless Chrome (stdlib only).

Usage:
    python render_ba_brief_pdf.py           # English
    python render_ba_brief_pdf.py --fa     # Persian (RTL)
"""
import argparse
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHROME = Path(r"C:/Program Files/Google/Chrome/Application/chrome.exe")

VAZIRMATN = "https://fonts.googleapis.com/css2?family=Vazirmatn:wght@400;500;600;700&display=swap"


def md_to_html(text: str) -> str:
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    in_table = False
    in_ul = False

    def inline(s: str) -> str:
        s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"`([^`]+)`", r'<code class="ltr">\1</code>', s)
        s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
        return s

    while i < len(lines):
        line = lines[i]
        if line.startswith("|") and "|" in line[1:]:
            if in_ul:
                out.append("</ul>")
                in_ul = False
            if not in_table:
                out.append("<table>")
                in_table = True
            cells = [inline(c.strip()) for c in line.strip().strip("|").split("|")]
            if all(re.match(r"^:?-+:?$", c.replace(" ", "")) for c in cells):
                i += 1
                continue
            is_header = out[-1] == "<table>"
            tag = "th" if is_header else "td"
            out.append("<tr>" + "".join(f"<{tag}>{c}</{tag}>" for c in cells) + "</tr>")
            i += 1
            continue
        if in_table:
            out.append("</table>")
            in_table = False

        if line.startswith("### "):
            if in_ul:
                out.append("</ul>")
                in_ul = False
            out.append(f"<h3>{inline(line[4:])}</h3>")
        elif line.startswith("## "):
            if in_ul:
                out.append("</ul>")
                in_ul = False
            out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("# "):
            if in_ul:
                out.append("</ul>")
                in_ul = False
            out.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.strip() == "---":
            out.append("<hr/>")
        elif line.startswith("- [ ] "):
            out.append(f"<p>☐ {inline(line[6:])}</p>")
        elif line.startswith("- [x] "):
            out.append(f"<p>☑ {inline(line[6:])}</p>")
        elif line.startswith("- "):
            if not in_ul:
                out.append("<ul>")
                in_ul = True
            out.append(f"<li>{inline(line[2:])}</li>")
        elif line.strip() == "":
            pass
        else:
            if in_ul:
                out.append("</ul>")
                in_ul = False
            out.append(f"<p>{inline(line)}</p>")
        i += 1

    if in_table:
        out.append("</table>")
    if in_ul:
        out.append("</ul>")
    return "\n".join(out)


def build_html(body: str, *, rtl: bool) -> str:
    if rtl:
        return f"""<!doctype html>
<html lang="fa" dir="rtl"><head><meta charset="utf-8"/>
<link href="{VAZIRMATN}" rel="stylesheet"/>
<title>FibonAI — خلاصه تحلیلگر کسب‌وکار</title>
<style>
@page {{ margin: 16mm 14mm; }}
body {{
  font: 11pt/1.75 'Vazirmatn', Tahoma, sans-serif;
  color: #1a1c20;
  direction: rtl;
  text-align: right;
}}
h1 {{ font: 700 20pt 'Vazirmatn', sans-serif; border-bottom: 2px solid #cdae6f; padding-bottom: 6px; }}
h2 {{ font: 600 14pt 'Vazirmatn', sans-serif; margin-top: 1.3em; color: #262f38; page-break-after: avoid; }}
h3 {{ font: 600 12pt 'Vazirmatn', sans-serif; page-break-after: avoid; }}
table {{ border-collapse: collapse; width: 100%; font-size: 8.5pt; margin: 8px 0 12px; page-break-inside: avoid; }}
th, td {{ border: 1px solid #ccc; padding: 6px 8px; vertical-align: top; text-align: right; }}
th {{ background: #f7f5f0; }}
code.ltr, .ltr {{ direction: ltr; unicode-bidi: isolate; font: 9pt Consolas, monospace; background: #f0f0f0; padding: 1px 4px; }}
a {{ color: #806533; }}
hr {{ border: none; border-top: 1px solid #ddd; margin: 1.4em 0; }}
ul {{ padding-right: 1.2em; padding-left: 0; }}
</style></head><body>{body}</body></html>"""
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"/>
<title>FibonAI — Business Analyst Brief</title>
<style>
@page {{ margin: 18mm 16mm; }}
body {{ font: 11pt/1.55 Georgia, 'Times New Roman', serif; color: #1a1c20; }}
h1 {{ font: 600 22pt system-ui, sans-serif; border-bottom: 2px solid #cdae6f; padding-bottom: 6px; }}
h2 {{ font: 600 14pt system-ui, sans-serif; margin-top: 1.4em; color: #262f38; page-break-after: avoid; }}
h3 {{ font: 600 12pt system-ui, sans-serif; page-break-after: avoid; }}
table {{ border-collapse: collapse; width: 100%; font-size: 9pt; margin: 8px 0 12px; page-break-inside: avoid; }}
th, td {{ border: 1px solid #ccc; padding: 6px 8px; vertical-align: top; }}
th {{ background: #f7f5f0; text-align: left; }}
code.ltr {{ font: 9pt Consolas, monospace; background: #f0f0f0; padding: 1px 4px; }}
a {{ color: #806533; }}
hr {{ border: none; border-top: 1px solid #ddd; margin: 1.5em 0; }}
ul {{ padding-left: 1.2em; }}
</style></head><body>{body}</body></html>"""


def render(md: Path, html: Path, pdf: Path, *, rtl: bool) -> None:
    body = md_to_html(md.read_text(encoding="utf-8"))
    html.write_text(build_html(body, rtl=rtl), encoding="utf-8")
    subprocess.run(
        [
            str(CHROME),
            "--headless=new",
            "--disable-gpu",
            f"--print-to-pdf={pdf}",
            "--no-pdf-header-footer",
            html.as_uri(),
        ],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fa", action="store_true", help="Persian RTL output")
    args = parser.parse_args()
    if args.fa:
        md = HERE / "FibonAI-Business-Analyst-Brief.fa.md"
        html = HERE / "FibonAI-Business-Analyst-Brief.fa.html"
        pdf = HERE / "FibonAI-Business-Analyst-Brief.fa.pdf"
        render(md, html, pdf, rtl=True)
    else:
        md = HERE / "FibonAI-Business-Analyst-Brief.md"
        html = HERE / "FibonAI-Business-Analyst-Brief.html"
        pdf = HERE / "FibonAI-Business-Analyst-Brief.pdf"
        render(md, html, pdf, rtl=False)
    print(pdf)


if __name__ == "__main__":
    main()
