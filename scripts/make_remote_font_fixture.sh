#!/bin/sh
# Builds a one-font remote endpoint fixture: a font renamed to a family no bundled
# tree can contain, plus the index that maps that name onto it.
set -eu

OUT=${1:?Usage: $0 <output-dir>}
PYTHON=${PYTHON:-python3}
FONTS_DIR=${FONTS_DIR:-/usr/share/fonts}

FAMILY='Busytex Smoke'
PSNAME='BusytexSmoke-Regular'

SOURCE_FONT=$(find "$FONTS_DIR" -type f \( -name '*.otf' -o -name '*.ttf' \) | sort | head -n 1)
[ -n "$SOURCE_FONT" ] || { echo "make_remote_font_fixture: no font below $FONTS_DIR" >&2; exit 1; }

case $SOURCE_FONT in
    *.otf) SUBDIR=opentype; TESTFONT="$PSNAME.otf" ;;
    *)     SUBDIR=truetype; TESTFONT="$PSNAME.ttf" ;;
esac

rm -rf "$OUT"
mkdir -p "$OUT" "$OUT/.texmf-dist/fonts/$SUBDIR"

$PYTHON - "$SOURCE_FONT" "$OUT/.texmf-dist/fonts/$SUBDIR/$TESTFONT" "$FAMILY" "$PSNAME" <<'PYEOF'
import sys
from fontTools.ttLib import TTFont

source, target, family, psname = sys.argv[1:5]
font = TTFont(source)
table = font["name"]
table.names = [record for record in table.names if record.nameID not in (1, 2, 4, 6, 16, 17)]
for name_id, value in ((1, family), (2, "Regular"), (4, family + " Regular"), (6, psname)):
    table.setName(value, name_id, 3, 1, 0x409)
    table.setName(value, name_id, 1, 0, 0)
font.save(target)
PYEOF

$PYTHON scripts/build_font_index.py --texmf-dist "$OUT/.texmf-dist" --output "$OUT/busytex-fontindex.txt"
cp "$OUT/.texmf-dist/fonts/$SUBDIR/$TESTFONT" "$OUT/$TESTFONT"
rm -rf "$OUT/.texmf-dist"

echo "make_remote_font_fixture: $OUT holds $TESTFONT and busytex-fontindex.txt"
