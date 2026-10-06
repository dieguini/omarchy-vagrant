#!/usr/bin/env python3
"""Redact a screenshot before it is saved or shared.

Finds words with tesseract (OCR) and pixelates them with ImageMagick, in place or into a
new file. Two modes:

  sensitive (default)  only words that look like secrets or personal data: emails, IPs,
                       GUIDs, long tokens/hashes, URLs with query strings, phone numbers,
                       the word after "password"/"token"/"secret"/"key", plus any term
                       listed in the terms file (one per line: names, customers...):
                       $REDACT_TERMS, else ~/.config/redact-shot/terms.txt
  all (--all)          every word on the image; only layout and images stay readable

usage: redact-shot.py IMAGE [-o OUT] [--all] [--pad N] [--dry-run]
       (no -o: the image is overwritten, so the unredacted version is never kept)

Needs: tesseract (+ any tesseract-data-* languages installed; eng and spa are used when
present) and ImageMagick `magick`. Python standard library only.
OCR is not perfect: tiny, rotated or low-contrast text can be missed. Check the result
before sharing anything sensitive; --all is the safe choice for evidence leaving the org.
"""
import argparse, csv, io, os, re, subprocess, sys

PATTERNS = [
    re.compile(r"[\w.+-]+@[\w-]{2,}(?:\.[\w.-]*)?"),                  # email (also truncated: name@domain...)
    re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?\b"),          # IPv4 / CIDR
    re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"),  # GUID
    re.compile(r"\b[0-9a-fA-F]{24,}\b"),                              # hex hash / thumbprint
    re.compile(r"\b[A-Za-z0-9_\-+/=]{28,}\b"),                        # long token / base64
    re.compile(r"https?://\S*[?&]\S+"),                               # URL with query string
    re.compile(r"\+?\d[\d\s().-]{8,}\d"),                             # phone number
]
KEYWORDS = re.compile(r"^(password|passwd|pwd|token|secret|apikey|api_key|key|passcode|pin)[:=]?$", re.I)


def ocr_once(image, lang, psm):
    tsv = subprocess.run(["tesseract", image, "stdout", "-l", lang, "--psm", str(psm), "tsv"],
                         capture_output=True, text=True, check=True).stdout
    words = []
    for r in csv.DictReader(io.StringIO(tsv), delimiter="\t", quoting=csv.QUOTE_NONE):
        t = (r.get("text") or "").strip()
        if t and r["level"] == "5" and float(r["conf"]) > 0:
            words.append((t, int(r["left"]), int(r["top"]), int(r["width"]), int(r["height"])))
    return words


def overlaps(a, b):
    ax, ay, aw, ah = a[1:]; bx, by, bw, bh = b[1:]
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah


# OCR passes merged into one word list. One pass misses text the others find: sparse mode
# (11) catches scattered labels, auto layout (3) catches buttons and rows, and the gray
# negative catches light text on dark backgrounds (selected rows, dark themes). The alpha
# channel is dropped first: -negate on a transparent PNG would leave nothing to read.
PASSES = [("-alpha off", 11), ("-alpha off", 3),
          ("-alpha off -colorspace gray -negate -threshold 60%", 3)]


def ocr(image):
    langs = subprocess.run(["tesseract", "--list-langs"], capture_output=True, text=True).stdout.split()
    lang = "+".join(l for l in ("eng", "spa") if l in langs) or "eng"
    words, tmp = [], image + ".ocr.png"
    try:
        for prep, psm in PASSES:
            subprocess.run(["magick", image, *prep.split(), tmp], check=True)
            words += [w for w in ocr_once(tmp, lang, psm) if not any(overlaps(w, x) for x in words)]
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return words


def load_terms():
    p = os.environ.get("REDACT_TERMS") or os.path.expanduser("~/.config/redact-shot/terms.txt")
    if not os.path.exists(p):
        return []
    return [l.strip().lower() for l in open(p, encoding="utf-8") if l.strip() and not l.startswith("#")]


def pick(words, all_words):
    if all_words:
        return list(range(len(words)))
    terms = load_terms()
    hit = set()
    for i, (t, *_ ) in enumerate(words):
        low = t.lower().strip(".,;:()[]\"'")
        if any(p.search(t) for p in PATTERNS) or any(term and term in low for term in terms):
            hit.add(i)
        if KEYWORDS.match(low) and i + 1 < len(words):   # the value right after "password:" etc.
            hit.add(i + 1)
    return sorted(hit)


def main():
    a = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    a.add_argument("image"); a.add_argument("-o", "--out")
    a.add_argument("--all", action="store_true", help="pixelate every word")
    a.add_argument("--pad", type=int, default=3, help="pixels added around each word")
    a.add_argument("--dry-run", action="store_true", help="list what would be redacted")
    o = a.parse_args()

    words = ocr(o.image)
    idx = pick(words, o.all)
    if o.dry_run:
        for i in idx:
            print(f"would redact: {words[i][0]!r} at {words[i][1:]}")
        print(f"{len(idx)} of {len(words)} words"); return
    out = o.out or o.image
    if not idx:
        if out != o.image:
            subprocess.run(["magick", o.image, out], check=True)
        print(f"redacted 0 of {len(words)} words -> {out}"); return
    # pixelate each box: crop, scale down/up, composite back
    cmd = ["magick", o.image]
    for i in idx:
        _, x, y, w, h = words[i]
        x, y, w, h = max(0, x - o.pad), max(0, y - o.pad), w + 2 * o.pad, h + 2 * o.pad
        cmd += ["(", "+clone", "-crop", f"{w}x{h}+{x}+{y}", "+repage",
                "-scale", "8%", "-scale", f"{w}x{h}!", ")",
                "-geometry", f"+{x}+{y}", "-composite"]
    cmd.append(out)
    subprocess.run(cmd, check=True)
    print(f"redacted {len(idx)} of {len(words)} words -> {out}")


if __name__ == "__main__":
    sys.exit(main())
