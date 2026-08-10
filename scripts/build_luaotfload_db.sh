#!/bin/sh
# Builds the luaotfload font name database for the full TeX Live tree. Paths are
# stored relative to texmf so that lookups resolve through kpse at load time.
set -eu

TEXDIR=${1:?Usage: $0 <texlive-full-dir>}
BUSYTEX=${BUSYTEX:-build/native/busytex}

ROOT=$(pwd)
case $BUSYTEX in
    /*) ;;
    *) [ -x "$ROOT/$BUSYTEX" ] && BUSYTEX="$ROOT/$BUSYTEX" ;;
esac

TEXMFDIST="$ROOT/$TEXDIR/texmf-dist"
CONF_DIR="$TEXMFDIST/tex/luatex/luaotfload"
CACHE_DIR="$TEXMFDIST/texmf-var/luatex-cache/generic/names"
TOOL="$TEXMFDIST/scripts/luaotfload/luaotfload-tool.lua"

if [ ! -f "$TOOL" ]; then
    echo "build_luaotfload_db: $TOOL is missing, run before the scripts tree is pruned" >&2
    exit 1
fi

mkdir -p "$CONF_DIR" "$CACHE_DIR"

cat > "$CONF_DIR/luaotfload.conf" << 'CONF'
[db]
location-precedence = texmf
update-live = false
formats = otf,ttf,ttc
CONF

cd "$TEXDIR"
TEXMFDIST="$TEXMFDIST" \
TEXMFVAR="$TEXMFDIST/texmf-var" \
TEXMFCACHE="$TEXMFDIST/texmf-var" \
TEXMFCNF="$TEXMFDIST/web2c" \
    "$BUSYTEX" luahbtex --luaonly "$TOOL" --update --force
cd "$ROOT"

DB=$(ls "$CACHE_DIR"/luaotfload-names.lua.gz "$CACHE_DIR"/luaotfload-names.lua 2>/dev/null | head -n 1 || true)
if [ -z "$DB" ]; then
    echo "build_luaotfload_db: no database written below $CACHE_DIR" >&2
    ls -la "$CACHE_DIR" >&2 || true
    exit 1
fi

BYTES=$(wc -c < "$DB")
if [ "$BYTES" -lt 262144 ]; then
    echo "build_luaotfload_db: $DB is only $BYTES bytes, the scan found almost nothing" >&2
    exit 1
fi

echo "build_luaotfload_db: $DB ($BYTES bytes)"
