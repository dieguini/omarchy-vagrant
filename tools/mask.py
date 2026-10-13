#!/usr/bin/env python3
"""Reversible masking for text that leaves the VM: prompts, delegated agents, tickets.

  mask mask   <in> <out> [--map NAME] [--terms FILE]
  mask unmask <in> <out> [--map NAME]
  mask selftest

Replaces IPs, emails, GUIDs, Azure resource IDs, URL query strings, UNC hosts and every
term listed in the terms file (one per line: servers, databases, customers, people) with
stable tokens such as <IP_1>. The same map reused across files gives the same token for the
same value, so masked outputs stay comparable. Values after password=/pwd=/secret=/token=
become <REDACTED> and are never stored in the map. Maps live in ~/.config/mask/maps/
(mode 600) and are never printed.
"""
import argparse, json, os, re, sys, tempfile

HOME = os.path.expanduser("~/.config/mask")
DEFAULT_TERMS = os.path.join(HOME, "terms.txt")

SECRET = re.compile(r"(?i)\b((?:password|passwd|pwd|secret|token|accountkey|sig|apikey|api_key)\s*[=:]\s*)([^\s;\"'&<>]+)")
PATTERNS = [  # order matters: the most specific first
    ("RESID", re.compile(r"(?i)/subscriptions/[0-9a-f-]{36}(?:/[\w.\-()]+)*")),
    ("EMAIL", re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")),
    ("GUID", re.compile(r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")),
    ("QUERY", re.compile(r"(?<=\?)[^\s\"'<>]+")),
    ("UNC", re.compile(r"(?<=\\\\)[\w.-]+")),
    ("IP", re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?\b")),
    ("IP6", re.compile(r"(?i)\b(?:[0-9a-f]{1,4}:){2,7}[0-9a-f]{1,4}\b")),
]
TOKEN = re.compile(r"<([A-Z0-9]+)_(\d+)>")


def map_path(name):
    if os.sep in name or name.endswith(".json"):
        return name
    return os.path.join(HOME, "maps", f"{name}.json")


def load_map(path):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {"forward": {}, "counters": {}}


def save_map(path, m):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        json.dump(m, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def load_terms(path):
    if not path or not os.path.exists(path):
        return []
    with open(path) as f:
        terms = [t.strip() for t in f if t.strip() and not t.startswith("#")]
    return sorted(set(terms), key=len, reverse=True)  # longest first


def token_for(m, kind, value):
    key = f"{kind}\0{value}"
    if key not in m["forward"]:
        n = m["counters"].get(kind, 0) + 1
        m["counters"][kind] = n
        m["forward"][key] = f"<{kind}_{n}>"
    return m["forward"][key]


def mask_text(text, m, terms):
    text = SECRET.sub(lambda x: x.group(1) + "<REDACTED>", text)
    for term in terms:
        text = re.sub(r"(?i)(?<![\w-])" + re.escape(term) + r"(?![\w-])",
                      lambda x: token_for(m, "TERM", x.group(0).lower()), text)
    for kind, rx in PATTERNS:
        text = rx.sub(lambda x, k=kind: x.group(0) if TOKEN.fullmatch(x.group(0)) else token_for(m, k, x.group(0)), text)
    return text


def unmask_text(text, m):
    back = {tok: key.split("\0", 1)[1] for key, tok in m["forward"].items()}
    return TOKEN.sub(lambda x: back.get(x.group(0), x.group(0)), text)


def selftest():
    sample = ("RDP from 193.0.2.10 to 10.3.0.4 failed for ana@example.com on web-a; "
              "see /subscriptions/00000000-1111-2222-3333-444444444444/resourceGroups/rg-x/providers/"
              "Microsoft.Compute/virtualMachines/web-a and \\\\fileserver\\share. "
              "Server=sql-a;Password=Sup3rS3cret;Database=Db_A https://h.example.com/x?sig=abc&se=1")
    with tempfile.TemporaryDirectory() as d:
        mp = os.path.join(d, "m.json")
        m = load_map(mp)
        masked = mask_text(sample, m, ["web-a", "sql-a", "Db_A"])
        save_map(mp, m)
        for leak in ["193.0.2.10", "ana@example.com", "web-a", "sql-a", "Db_A", "Sup3rS3cret", "fileserver", "sig=abc"]:
            assert leak not in masked, f"leak: {leak}"
        assert "<REDACTED>" in masked
        stored = open(mp).read()
        assert "Sup3rS3cret" not in stored, "secret stored in map"
        assert oct(os.stat(mp).st_mode & 0o777) == "0o600"
        restored = unmask_text(masked, load_map(mp))
        expected = SECRET.sub(lambda x: x.group(1) + "<REDACTED>", sample)
        assert restored.lower() == expected.lower(), (restored, expected)
        again = mask_text("10.3.0.4 again", load_map(mp), [])
        assert again.startswith(masked.split("to ")[1].split(" ")[0]), "token not stable across runs"
    print("mask.py selftest: PASS")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["mask", "unmask", "selftest"])
    ap.add_argument("src", nargs="?")
    ap.add_argument("dst", nargs="?")
    ap.add_argument("--map", default="default")
    ap.add_argument("--terms", default=DEFAULT_TERMS)
    a = ap.parse_args()
    if a.cmd == "selftest":
        return selftest()
    if not (a.src and a.dst):
        ap.error("mask/unmask need <in> <out>")
    text = open(a.src, encoding="utf-8", errors="replace").read()
    mp = map_path(a.map)
    m = load_map(mp)
    if a.cmd == "mask":
        out = mask_text(text, m, load_terms(a.terms))
        save_map(mp, m)
    else:
        out = unmask_text(text, m)
    with open(a.dst, "w", encoding="utf-8") as f:
        f.write(out)
    print(f"{a.cmd}: {a.dst} (map: {os.path.basename(mp)})")


if __name__ == "__main__":
    sys.exit(main())
