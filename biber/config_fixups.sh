#!/bin/sh
# Applied to perl's config.sh after Configure and before make.
#
# Two classes of correction:
#
# 1. Symbols Configure reports as present because emcc tolerates undefined
#    symbols at link time, while the emscripten sysroot headers never declare
#    them. emcc >= 2.0 makes implicit declarations an error, so the core build
#    fails on them. Verified absent from $EMSDK_SYSROOT/include.
#
# 2. The INF/NAN byte-pattern probes run a test program under node and fail to
#    parse its output, leaving the literal string "undef", which perl emits as
#    "#define DOUBLEINFBYTES undef". Configure does get doublekind=3 (IEEE 754
#    64-bit little endian) and longdblkind=1 (IEEE 754 128-bit little endian)
#    right, so the patterns are the standard ones for those formats.
set -e
CONFIG_SH=${1:-config.sh}

for sym in setproctitle setruid setrgid fdclose malloc_size malloc_good_size; do
    sed -i -E "s/^d_${sym}='define'/d_${sym}='undef'/" "$CONFIG_SH"
done

sed -i -E "s/^d_sigaction='undef'/d_sigaction='define'/" "$CONFIG_SH"

set_var() {
    sed -i -E "s|^$1='.*'$|$1='$2'|" "$CONFIG_SH"
}

set_var doubleinfbytes  "0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xf0, 0x7f"
set_var doublenanbytes  "0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xf8, 0x7f"
set_var longdblinfbytes "0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xff, 0x7f"
set_var longdblnanbytes "0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x80, 0xff, 0x7f"
