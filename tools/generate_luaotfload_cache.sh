#!/usr/bin/env bash
set -euo pipefail

TEXMF_ROOT="${1:?usage: $0 <texmf-root> <out-dir> <busytex-bin>}"
OUT_DIR="${2:?}"
BUSYTEX="${3:?}"

TEXMF_ROOT=$(realpath "$TEXMF_ROOT")
OUT_DIR=$(realpath -m "$OUT_DIR")
BUSYTEX=$(realpath "$BUSYTEX")

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

bwrap \
  --ro-bind /usr /usr \
  --ro-bind /lib /lib \
  --ro-bind-try /lib64 /lib64 \
  --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --tmpfs /texlive \
  --ro-bind "$BUSYTEX" /tmp/busytex \
  --ro-bind "$TEXMF_ROOT" /texlive/texmf-dist \
  --bind "$OUT_DIR" /texlive/cache \
  --setenv TEXMFCNF /texlive/texmf-dist/web2c \
  --setenv TEXMFDIST /texlive/texmf-dist \
  --setenv TEXMFVAR /texlive/cache \
  --setenv TEXMFCACHE /texlive/cache \
  --setenv OSFONTDIR "" \
  --setenv HOME /tmp \
  /tmp/busytex luahbtex --luaonly \
    /texlive/texmf-dist/scripts/luaotfload/luaotfload-tool.lua \
    --update --force 2>&1 | tail -5

ls "$OUT_DIR/luatex-cache/generic/names/luaotfload-names.lua.gz"
echo "luaotfload cache generated"