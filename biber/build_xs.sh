#!/bin/bash
# Build one CPAN XS module as a static extension for the wasm perl.
#
# Modules are NOT dropped into perl's cpan/ tree: that makes the perl build run
# their Makefile.PL under miniperl, which cannot load the XS IO::File that
# inc::latest and Module::Build require. Instead the .c is generated with a host
# xsubpp, compiled with emcc against the target CORE headers, and archived where
# perl's static_ext machinery expects it.
#
# usage: MODVER=1.19 build_xs.sh <srcdir> <Module::Name> [extra emcc flags]
#
# MODVER must match the version in the module's .pm or the XS bootstrap check
# fails at runtime with "object version 0 does not match bootstrap parameter".
set -u
SRC=$1; MOD=$2; shift 2
EXTRA="${*:-}"
MODVER=${MODVER:-0}
PERL_WASM_PREFIX=${PERL_WASM_PREFIX:?set PERL_WASM_PREFIX}
PERL_WASM_VERSION=${PERL_WASM_VERSION:?set PERL_WASM_VERSION}
PERL_WASM_LIB=${PERL_WASM_LIB:?set PERL_WASM_LIB}
HOST_PERL=${HOST_PERL:-perl}
AR=${AR:-llvm-ar}

CORE=$PERL_WASM_PREFIX/lib/$PERL_WASM_VERSION/wasm/CORE
HOST_TYPEMAP=$($HOST_PERL -MConfig -e 'print "$Config{privlib}/ExtUtils/typemap"')
LEAF=${MOD##*::}
PATHPART=${MOD//:://}
OUT=$PERL_WASM_LIB/auto/$PATHPART

cd "$SRC" || exit 1
mkdir -p "$OUT"
objs=""
generated=""

# Only top-level .xs files: XS/*.xs and similar are pulled in via INCLUDE: and
# must not be compiled as translation units of their own.
for xs in $(find . -maxdepth 1 -name '*.xs'); do
    tm=""
    [ -f typemap ] && tm=typemap
    $HOST_PERL -MExtUtils::ParseXS -e '
        my ($f, $o, $tmap, $extra) = @ARGV;
        my @tm = ($tmap);
        push @tm, $extra if $extra;
        ExtUtils::ParseXS->new->process_file(filename => $f, output => $o, typemap => \@tm);
    ' "$xs" "${xs%.xs}.c" "$HOST_TYPEMAP" "$tm" 2>/dev/null
    [ -s "${xs%.xs}.c" ] || { echo "XSUBPP-FAIL $MOD $xs"; exit 2; }
    generated="$generated ${xs%.xs}.c"
done

for c in $(find . -maxdepth 1 -name '*.c' -not -name 'conftest*') $generated; do
    o=${c%.c}.o
    emcc -c -O1 -I. -I"$CORE" $EXTRA \
        -DVERSION="\"$MODVER\"" -DXS_VERSION="\"$MODVER\"" \
        -o "$o" "$c" || { echo "CC-FAIL $MOD $c"; exit 3; }
    objs="$objs $o"
done

$AR rcs "$OUT/$LEAF.a" $objs || exit 4
echo "OK $MOD -> $OUT/$LEAF.a"
