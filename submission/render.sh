#!/bin/sh
# Renders thumbnail.html to thumbnail.png at exactly 1800x1200 and verifies the result.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/thumbnail.html"
OUT="$DIR/thumbnail.png"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

rm -f "$OUT"

"$CHROME" \
  --headless \
  --disable-gpu \
  --hide-scrollbars \
  --force-device-scale-factor=1 \
  --screenshot="$OUT" \
  --window-size=1800,1200 \
  --default-background-color=00000000 \
  "file://$SRC"

python3 - "$OUT" <<'PY'
import os, sys
from PIL import Image
p = sys.argv[1]
im = Image.open(p)
size = os.path.getsize(p)
print("size:", im.size)
print("bytes:", size, "(%.2f MB)" % (size / 1024 / 1024))
print("ok:", im.size == (1800, 1200) and size < 5 * 1024 * 1024)

# Devpost-tile legibility check: the motif has to survive this reduction.
tile = im.convert("RGB").resize((450, 300), Image.LANCZOS)
tile.save(os.path.join(os.path.dirname(p), "thumbnail-tilecheck.png"))
print("tilecheck:", tile.size)
PY
