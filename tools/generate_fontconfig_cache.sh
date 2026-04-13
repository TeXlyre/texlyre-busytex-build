#!/usr/bin/env bash
set -euo pipefail

TEXMF_ROOT="${1:?usage: $0 <texmf-root> <out-dir> <fc-cache-bin>}"
OUT_DIR="${2:?}"
FC_CACHE="${3:?}"

TEXMF_ROOT=$(realpath "$TEXMF_ROOT")
OUT_DIR=$(realpath -m "$OUT_DIR")
FC_CACHE=$(realpath "$FC_CACHE")

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/cache"

cat > "$OUT_DIR/fonts.conf" <<'EOF'
<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
<dir>/texlive/texmf-dist/fonts/opentype</dir>
<dir>/texlive/texmf-dist/fonts/truetype</dir>
<dir>/texlive/texmf-dist/fonts/type1</dir>
<cachedir>/texlive/fontconfig-cache</cachedir>
</fontconfig>
EOF

bwrap \
  --ro-bind /usr /usr \
  --ro-bind /lib /lib \
  --ro-bind-try /lib64 /lib64 \
  --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --tmpfs /texlive \
  --ro-bind "$FC_CACHE" /tmp/fc-cache \
  --bind "$TEXMF_ROOT/fonts" /texlive/texmf-dist/fonts \
  --bind "$OUT_DIR/cache" /texlive/fontconfig-cache \
  --ro-bind "$OUT_DIR/fonts.conf" /texlive/fonts.conf \
  --setenv FONTCONFIG_PATH /texlive \
  --setenv FONTCONFIG_FILE /texlive/fonts.conf \
  /tmp/fc-cache -f 2>&1 | tail -3

count=$(ls "$OUT_DIR/cache"/*.cache-8 2>/dev/null | wc -l)
echo "fontconfig cache: $count cache-8 files generated"
test "$count" -gt 0