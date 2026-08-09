#!/bin/sh
# Verifies the font index path natively: with fontconfig starved of every font,
# a by-name lookup must fail without the index and succeed with it.
set -eu

BUSYTEX=${BUSYTEX:-build/native/busytex}
XETEX_APPLET=${XETEX_APPLET-xetex}
PYTHON=${PYTHON:-python3}
FONTS_DIR=${1:-/usr/share/fonts}
WORK=${WORK:-build/smoke-fontindex}
MAX_FONTS=${MAX_FONTS:-40}

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
    echo "smoke-fontindex: cannot run [$BUSYTEX $XETEX_APPLET], output follows" >&2
    $BUSYTEX $XETEX_APPLET --version >&2 2>&1 || true
    exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK/texmf-dist/fonts/opentype" "$WORK/texmf-dist/fonts/truetype" \
         "$WORK/with-index" "$WORK/without-index" "$WORK/fontconfig/cache"

find "$FONTS_DIR" -type f \( -name '*.otf' -o -name '*.otc' -o -name '*.ttf' -o -name '*.ttc' \) \
    | sort | head -n "$MAX_FONTS" | while read -r font; do
    case $font in
        *.otf|*.otc) sub=opentype ;;
        *)           sub=truetype ;;
    esac
    cp "$font" "$WORK/texmf-dist/fonts/$sub/"
    cp "$font" "$WORK/with-index/"
    cp "$font" "$WORK/without-index/"
done

if [ -z "$(ls -A "$WORK/with-index")" ]; then
    echo "smoke-fontindex: no usable fonts below $FONTS_DIR" >&2
    exit 1
fi

$PYTHON scripts/build_font_index.py \
    --texmf-dist "$WORK/texmf-dist" \
    --output "$WORK/with-index/busytex-fontindex.txt"

FONTNAME=$(sed -n '2p' "$WORK/with-index/busytex-fontindex.txt" | cut -f17 | cut -d'|' -f1)
if [ -z "$FONTNAME" ]; then
    echo "smoke-fontindex: generated index carries no font name" >&2
    exit 1
fi

printf '<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><cachedir>%s/%s/fontconfig/cache</cachedir></fontconfig>' \
    "$ROOT" "$WORK" > "$WORK/fontconfig/fonts.conf"

for dir in with-index without-index; do
    cat > "$WORK/$dir/test.tex" <<EOF
\\catcode\`\\{=1
\\catcode\`\\}=2
\\tracingonline=1
\\XeTeXtracingfonts=1
\\font\\testfont="$FONTNAME" at 10pt
\\testfont
\\end
EOF
done

run_case() {
    dir=$1
    cd "$ROOT/$dir"
    FONTCONFIG_FILE="$ROOT/$WORK/fontconfig/fonts.conf" \
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

report_case() {
    echo "smoke-fontindex: engine output from $1" >&2
    LC_ALL=C sed -n '1,40p' "$1/run.out" >&2 2>/dev/null || true
}

echo "smoke-fontindex: requesting \"$FONTNAME\" with fontconfig starved"

CONTROL=$(run_case "$WORK/without-index")
ACTUAL=$(run_case "$WORK/with-index")

echo "smoke-fontindex: without index -> $CONTROL"
echo "smoke-fontindex: with index    -> $ACTUAL"

if [ "$CONTROL" = "missing" ] || [ "$ACTUAL" = "missing" ]; then
    echo "smoke-fontindex: FAIL, the engine produced no log" >&2
    report_case "$WORK/without-index"
    exit 1
fi

if [ "$CONTROL" != "unresolved" ]; then
    echo "smoke-fontindex: FAIL, the control run resolved the font without the index" >&2
    exit 1
fi

if [ "$ACTUAL" != "resolved" ]; then
    echo "smoke-fontindex: FAIL, the index did not resolve the font" >&2
    report_case "$WORK/with-index"
    exit 1
fi

echo "smoke-fontindex: PASS"
