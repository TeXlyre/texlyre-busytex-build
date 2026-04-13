#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_DIR="${1:?usage: $0 <archive-dir> <texmf-root>}"
TEXMF_ROOT="${2:?}"

luaotfload_tar=$(ls "$ARCHIVE_DIR"/luaotfload.r*.tar.xz | grep -v '\.doc\.' | grep -v '\.source\.' | head -1)
altgetopt_tar=$(ls "$ARCHIVE_DIR"/lua-alt-getopt.r*.tar.xz | grep -v '\.doc\.' | grep -v '\.source\.' | head -1)

mkdir -p "$TEXMF_ROOT/texmf-dist/scripts/luaotfload" \
         "$TEXMF_ROOT/texmf-dist/scripts/lua-alt-getopt"

tar -xJOf "$luaotfload_tar" texmf-dist/scripts/luaotfload/luaotfload-tool.lua \
  > "$TEXMF_ROOT/texmf-dist/scripts/luaotfload/luaotfload-tool.lua"

tar -xJOf "$altgetopt_tar" scripts/lua-alt-getopt/alt_getopt.lua \
  > "$TEXMF_ROOT/texmf-dist/scripts/lua-alt-getopt/alt_getopt.lua"

if command -v mktexlsr >/dev/null 2>&1; then
    mktexlsr "$TEXMF_ROOT/texmf-dist" >/dev/null 2>&1 || true
fi

echo "installed luaotfload-tool.lua and alt_getopt.lua into $TEXMF_ROOT"