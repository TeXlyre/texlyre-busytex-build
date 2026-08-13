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

# hints/emscripten.sh sets d_sigaction='undef', which was true of emscripten
# 1.37 but is not any more: sigaction, siginfo_t and SA_SIGINFO are all present
# and a real sigaction call links and returns 0. Leaving it undef makes perl.h
# fall back to its dummy one-field Siginfo_t while ext/POSIX/POSIX.xs still
# compiles its sigaction branch, which it guards on SA_SIGINFO from the system
# header alone - the two disagree and POSIX.o fails with incompatible function
# pointer types on act.sa_sigaction.
#
# Signals stay effectively disabled regardless: PerlProc_signal is still routed
# through Perl_Emscripten_signal by patches/02.
sed -i -E "s/^d_sigaction='undef'/d_sigaction='define'/" "$CONFIG_SH"

set_var() {
    sed -i -E "s|^$1='.*'$|$1='$2'|" "$CONFIG_SH"
}

set_var doubleinfbytes  "0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xf0, 0x7f"
set_var doublenanbytes  "0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xf8, 0x7f"
set_var longdblinfbytes "0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xff, 0x7f"
set_var longdblnanbytes "0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x80, 0xff, 0x7f"

# Tie::Hash::NamedCapture was an XS extension through 5.30 and is pure perl from
# 5.32 on: ext/Tie-Hash-NamedCapture ships only NamedCapture.pm, so make_ext
# builds no archive and the link fails on a missing NamedCapture.a. The static
# extension list in hints/emscripten.sh predates that change.
sed -i -E "s|Tie/Hash/NamedCapture ||" "$CONFIG_SH"

# Emscripten has no stack protector: __stack_chk_guard is undefined at link even
# for a trivial program. Configure adds -fstack-protector-strong by default and
# hints/emscripten.sh repeats it in its hardcoded cppflags, so it is stripped
# from every flag variable at once.
sed -i "s/ -fstack-protector-strong//g" "$CONFIG_SH"
