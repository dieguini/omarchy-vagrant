# redact-shot

`redact-shot` pixelates text in a screenshot before you save or share it. It finds
words with OCR (tesseract) and blurs them with ImageMagick, in place by default, so
the unredacted image is never kept.

It is installed by default (`"redact_shot": true` in `config.json`). It is small:
tesseract with English data, ImageMagick, and one Python file that uses only the
standard library. Set `"redact_shot": false` in `config.local.json` to skip it.

## Use

```bash
redact-shot shot.png                 # sensitive mode, overwrites shot.png
redact-shot shot.png -o safe.png     # keep the original, write a redacted copy
redact-shot shot.png --all           # pixelate every word
redact-shot shot.png --dry-run       # list what would be redacted, change nothing
```

Two modes:

| Mode | What gets pixelated |
|---|---|
| sensitive (default) | Emails, IPv4 addresses and CIDRs, GUIDs, long hex strings (hashes, thumbprints), long tokens and base64, URLs with a query string, phone numbers, the word after `password`, `token`, `secret`, `key` and similar, and every term in your terms file |
| `--all` | Every word. Only the layout and images stay readable. Use it for anything that leaves your organization |

### Your own terms

Names, customers, hostnames: put one per line in `~/.config/redact-shot/terms.txt`
(created empty by the provisioner), or point `REDACT_TERMS` at another file. Matching
is case-insensitive and on substrings, so `contoso` also catches `contoso-prod-01`.

```text
# ~/.config/redact-shot/terms.txt
contoso
jane.doe
db-prod
```

### Other languages

The provisioner installs English OCR data. For text in another language, add its
package, for example Spanish:

```bash
sudo pacman -S tesseract-data-spa
```

English and Spanish are used together when both are installed.

### From a script

Call it right after the capture, before anything else reads the file:

```bash
grim /tmp/shot.png && redact-shot /tmp/shot.png --all
```

## How it works

The image is read three times and the words are merged. Each pass catches text the
others miss:

1. Sparse mode (`--psm 11`): scattered labels.
2. Automatic layout (`--psm 3`): buttons, table rows, paragraphs.
3. Grayscale negative, automatic layout: light text on dark backgrounds (selected
   rows, dark themes).

The alpha channel is removed first, because negating a transparent PNG leaves nothing
to read. Each selected word box, plus a 3-pixel margin (`--pad`), is scaled down to 8%
and back up. A typical 1400×1200 screenshot takes about 2.5 seconds.

## Limits

OCR is not perfect. It can miss very small, rotated, stylized or low-contrast text, and
text inside images. Pixelation hides text from people reading the image; it is not a
guarantee against every recovery technique for short, predictable strings. Check the
result before sharing anything sensitive, and prefer `--all`, or crop the image, when
it matters.
