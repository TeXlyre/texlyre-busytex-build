#!/bin/sh
# Verifies the font index path natively. A font is renamed to a family no system
# font set can contain, so a by-name lookup can only succeed through the index.
set -eu

BUSYTEX=${BUSYTEX:-build/native/busytex}
XETEX_APPLET=${XETEX_APPLET-xetex}
PYTHON=${PYTHON:-python3}
FONTS_DIR=${1:-/usr/share/fonts}
WORK=${WORK:-build/smoke-fontindex}

FAMILY='Busytex Smoke'
FULLNAME='Busytex Smoke Regular'
PSNAME='BusytexSmoke-Regular'

if [ ! -d "$FONTS_DIR" ]; then
    echo "smoke-fontindex: no font directory at $FONTS_DIR" >&2
    exit 1
fi

ROOT=$(pwd)

case $BUSYTEX in
    /*) ;;
    *) [ -x "$ROOT/$BUSYTEX" ] && BUSYTEX="$ROOT/$BUSYTEX" ;;
esac

if ! $BUSYTEX $XETEX_APPLET --version > /dev/null 2>&1; then
    echo "smoke-fontindex: cannot run [$BUSYTEX $XETEX_APPLET], output follows"
    $BUSYTEX $XETEX_APPLET --version 2>&1 || true
    exit 1
fi

SOURCE_FONT=$(find "$FONTS_DIR" -type f \( -name '*.otf' -o -name '*.ttf' \) | sort | head -n 1)
if [ -z "$SOURCE_FONT" ]; then
    echo "smoke-fontindex: no .otf or .ttf font below $FONTS_DIR" >&2
    exit 1
fi

case $SOURCE_FONT in
    *.otf) SUBDIR=opentype; TESTFONT="$PSNAME.otf" ;;
    *)     SUBDIR=truetype; TESTFONT="$PSNAME.ttf" ;;
esac

rm -rf "$WORK"
mkdir -p "$WORK/texmf-dist/fonts/$SUBDIR" "$WORK/with-index" "$WORK/without-index"

$PYTHON - "$SOURCE_FONT" "$WORK/texmf-dist/fonts/$SUBDIR/$TESTFONT" \
         "$FAMILY" "$FULLNAME" "$PSNAME" <<'PYEOF'
import sys
from fontTools.ttLib import TTFont

source, target, family, fullname, psname = sys.argv[1:6]
font = TTFont(source)
table = font["name"]
table.names = [record for record in table.names if record.nameID not in (16, 17)]
for name_id, value in ((1, family), (2, "Regular"), (4, fullname), (6, psname)):
    table.setName(value, name_id, 3, 1, 0x409)
    table.setName(value, name_id, 1, 0, 0)
font.save(target)
PYEOF

cp "$WORK/texmf-dist/fonts/$SUBDIR/$TESTFONT" "$WORK/with-index/"
cp "$WORK/texmf-dist/fonts/$SUBDIR/$TESTFONT" "$WORK/without-index/"

$PYTHON scripts/build_font_index.py \
    --texmf-dist "$WORK/texmf-dist" \
    --output "$WORK/with-index/busytex-fontindex.txt"

for dir in with-index without-index; do
    cat > "$WORK/$dir/test.tex" <<EOF
\\catcode\`\\{=1
\\catcode\`\\}=2
\\tracingonline=1
\\XeTeXtracingfonts=1
\\font\\testfont="$FAMILY" at 10pt
\\testfont
\\end
EOF
done

run_case() {
    dir=$1
    cd "$ROOT/$dir"
    TEXINPUTS=. TEXFONTS=. OPENTYPEFONTS=. TTFONTS=. TYPE1FONTS=. \
        $BUSYTEX $XETEX_APPLET -ini -etex -no-pdf -interaction=nonstopmode test.tex \
        > run.out 2>&1 || true
    cd "$ROOT"
    if [ ! -f "$dir/test.log" ]; then
        echo "missing"
        return
    fi
    if LC_ALL=C grep -q 'not loadable' "$dir/test.log"; then
        echo "unresolved"
    else
        echo "resolved"
    fi
}

report() {
    for dir in "$WORK/without-index" "$WORK/with-index"; do
        echo "smoke-fontindex: ---- $dir ----"
        LC_ALL=C sed -n '1,40p' "$dir/run.out" 2>/dev/null || true
    done
}

echo "smoke-fontindex: renamed $(basename "$SOURCE_FONT") to \"$FAMILY\""

CONTROL=$(run_case "$WORK/without-index")
ACTUAL=$(run_case "$WORK/with-index")

echo "smoke-fontindex: without index -> $CONTROL"
echo "smoke-fontindex: with index    -> $ACTUAL"

if [ "$CONTROL" != "unresolved" ] || [ "$ACTUAL" != "resolved" ]; then
    report
    if [ "$CONTROL" != "unresolved" ]; then
        echo "smoke-fontindex: FAIL, the control run did not fail as it must" >&2
    else
        echo "smoke-fontindex: FAIL, the index did not resolve the font" >&2
    fi
    exit 1
fi

echo "smoke-fontindex: PASS"
