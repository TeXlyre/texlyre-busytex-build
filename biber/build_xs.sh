#!/bin/bash
# Builds one CPAN XS module as a static extension for the wasm perl.
# usage: MODVER=1.19 build_xs.sh <srcdir> <Module::Name> [extra emcc flags]
set -u
SRC=$1; MOD=$2; shift 2
EXTRA="${*:-}"
MODVER=${MODVER:-0}
PERL_WASM_CORE=${PERL_WASM_CORE:?set PERL_WASM_CORE}
PERL_WASM_LIB=${PERL_WASM_LIB:?set PERL_WASM_LIB}
HOST_PERL=${HOST_PERL:-perl}
HOST_TYPEMAP=${HOST_TYPEMAP:?set HOST_TYPEMAP}
AR=${AR:-llvm-ar}

LEAF=${MOD##*::}
PATHPART=${MOD//:://}
OUT=$PERL_WASM_LIB/auto/$PATHPART

cd "$SRC" || exit 1
mkdir -p "$OUT"
objs=""
generated=""

# Where top-level .xs exist, any others are pulled in via INCLUDE: and must not
# be compiled as translation units of their own.
xs_files=$(find . -maxdepth 1 -name '*.xs')
[ -n "$xs_files" ] || xs_files=$(find . -name '*.xs' -not -path './t/*')
[ -n "$xs_files" ] || { echo "NO-XS $MOD"; exit 2; }

for xs in $xs_files; do
    # ParseXS resolves a relative typemap against the .xs file's directory.
    tm=""
    [ -f "$(dirname "$xs")/typemap" ] && tm="$PWD/$(dirname "$xs")/typemap"
    [ -z "$tm" ] && [ -f typemap ] && tm="$PWD/typemap"
    $HOST_PERL -MExtUtils::ParseXS -e '
        my ($f, $o, $tmap, $extra) = @ARGV;
        my @tm = ($tmap);
        push @tm, $extra if $extra;
        ExtUtils::ParseXS->new->process_file(filename => $f, output => $o, typemap => \@tm);
    ' "$xs" "${xs%.xs}.c" "$HOST_TYPEMAP" "$tm"
    [ -s "${xs%.xs}.c" ] || { echo "XSUBPP-FAIL $MOD $xs"; exit 2; }
    generated="$generated ${xs%.xs}.c"
done

c_files=$(find . -maxdepth 1 -name '*.c' -not -name 'conftest*')
for xs in $xs_files; do
    d=$(dirname "$xs")
    [ "$d" = "." ] && continue
    c_files="$c_files $(find "$d" -maxdepth 1 -name '*.c' -not -name 'conftest*')"
done
c_files=$(printf '%s\n' $c_files $generated | sort -u)

for c in $c_files; do
    o=${c%.c}.o
    emcc -c -O1 -I. -I"$(dirname "$c")" -I"$PERL_WASM_CORE" $EXTRA \
        -DVERSION="\"$MODVER\"" -DXS_VERSION="\"$MODVER\"" \
        -o "$o" "$c" || { echo "CC-FAIL $MOD $c"; exit 3; }
    objs="$objs $o"
done

$AR rcs "$OUT/$LEAF.a" $objs || exit 4

# An empty archive means the .xs was never found; ar reports success and the
# failure only surfaces as a missing boot_ symbol at link time.
[ -n "$($AR t "$OUT/$LEAF.a")" ] || { echo "EMPTY-ARCHIVE $MOD"; exit 5; }
echo "OK $MOD -> $OUT/$LEAF.a"
