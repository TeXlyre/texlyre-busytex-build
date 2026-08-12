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

# A real TeX Live font that is in the generated luaotfload database but in none of the
# bundled packages: LuaHBTeX can only reach it by fetching it from the endpoint.
EXTRA_TREE=${EXTRA_TREE:-build/texlive-extra/texmf-dist}
BUNDLED_TREES=${BUNDLED_TREES:-build/texlive-basic/texmf-dist build/texlive-recommended/texmf-dist}
DB=${DB:-build/texlive-basic/texmf-dist/texmf-var/luatex-cache/generic/names/luaotfload-names.lua.gz}

if [ -d "$EXTRA_TREE" ] && [ -f "$DB" ]; then
    $PYTHON - "$OUT" "$EXTRA_TREE" "$DB" $BUNDLED_TREES <<'PYEOF'
import gzip
import os
import shutil
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

out, extra_tree, db_path = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
bundled_trees = [Path(p) for p in sys.argv[4:]]
SUFFIXES = (".otf", ".ttf")


def font_files(tree):
    for root in ("opentype", "truetype"):
        base = tree / "fonts" / root
        if base.is_dir():
            for dirpath, _, filenames in os.walk(base):
                for filename in sorted(filenames):
                    if filename.lower().endswith(SUFFIXES):
                        yield Path(dirpath) / filename


def family(path):
    try:
        with TTFont(str(path), lazy=True) as font:
            names = {r.nameID: r for r in font["name"].names if r.nameID in (1, 16)}
            record = names.get(16) or names.get(1)
            return str(record.toUnicode()).strip() if record else None
    except Exception:
        return None


database = gzip.open(db_path, "rt", errors="replace").read()
bundled_names, bundled_families = set(), set()
for tree in bundled_trees:
    for path in font_files(tree):
        bundled_names.add(path.name.lower())
        found = family(path)
        if found:
            bundled_families.add(found)

for path in sorted(font_files(extra_tree)):
    if path.name.lower() in bundled_names:
        continue
    found = family(path)
    if not found or found in bundled_families:
        continue
    if f'"{found}"' not in database:
        continue
    shutil.copy(path, out / path.name)
    (out / "example-luaotfload-remote.tex").write_text(
        "\\documentclass{article}\n"
        "\\usepackage{fontspec}\n"
        f"\\setmainfont{{{found}}}\n"
        "\\begin{document}\n"
        "LuaHBTeX selected this family by name and fetched it remotely.\n"
        "\\end{document}\n",
        encoding="utf-8",
    )
    print(f'make_remote_font_fixture: luaotfload target "{found}" via {path.name}')
    sys.exit(0)

sys.exit("make_remote_font_fixture: no font is both in the database and absent from every bundle")
PYEOF
else
    echo "make_remote_font_fixture: no extra tree or database, skipping the luaotfload fixture"
fi
