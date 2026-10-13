#!/usr/bin/env bash
# text-shot: renders a text file (a command's output: sqlcmd, az, kubectl, …) as a plain dark
# page in the CDP Chromium and saves a page-only screenshot, for evidence or a ticket. The
# desktop never appears in the image. Needs `chromium-cdp` running and `cdp` on PATH.
#
#   text-shot <output.txt> <shot.png> ["title line"]
#   REDACT=sensitive|all text-shot …     pixelate the screenshot with redact-shot
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: text-shot <output.txt> <shot.png> [\"title line\"]" >&2; exit 1; }
PORT=${CDP_PORT:-9222}
TXT=$(realpath "$1"); PNG=$(realpath -m "$2"); TITLE=${3:-$(basename "$TXT")}
curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null \
  || { echo "no Chromium DevTools on 127.0.0.1:$PORT -- start one with: chromium-cdp" >&2; exit 2; }
HTML=$(mktemp --suffix=.html /tmp/text-shot-XXXXXX)
id=""
trap 'rm -f "$HTML"; [ -n "$id" ] && curl -s "http://127.0.0.1:$PORT/json/close/$id" >/dev/null || true' EXIT
python3 - "$TXT" "$HTML" "$TITLE" <<'PY'
import html, sys, datetime
txt, out, title = sys.argv[1:]
body = html.escape(open(txt, encoding="utf-8", errors="replace").read())
stamp = datetime.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
open(out, "w").write(f"""<!doctype html><meta charset=utf-8><title>{html.escape(title)}</title>
<style>body{{margin:0;background:#0f1115;color:#e6e6e6;font:13px/1.45 ui-monospace,Menlo,Consolas,monospace}}
header{{padding:10px 16px;background:#1b1f27;border-bottom:1px solid #2c323d}}h1{{font-size:14px;margin:0}}
small{{color:#9aa4b2}}pre{{margin:0;padding:12px 16px;white-space:pre;column-width:58ch;column-gap:32px;column-rule:1px solid #2c323d;column-fill:auto;height:calc(100vh - 90px)}}</style>
<header><h1>{html.escape(title)}</h1><small>{stamp} · {html.escape(txt)}</small></header><pre>{body}</pre>""")
PY
id=$(curl -s -X PUT "http://127.0.0.1:$PORT/json/new?file://$HTML" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
sleep 2
CDP_URL_MATCH="$(basename "$HTML")" cdp shot "$PNG" >/dev/null
echo "$PNG"
