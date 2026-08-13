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
PERL_WASM_CORE=${PERL_WASM_CORE:?set PERL_WASM_CORE}
PERL_WASM_LIB=${PERL_WASM_LIB:?set PERL_WASM_LIB}
HOST_PERL=${HOST_PERL:-perl}
HOST_TYPEMAP=${HOST_TYPEMAP:?set HOST_TYPEMAP}
AR=${AR:-llvm-ar}

CORE=$PERL_WASM_CORE
LEAF=${MOD##*::}
PATHPART=${MOD//:://}
OUT=$PERL_WASM_LIB/auto/$PATHPART

cd "$SRC" || exit 1
mkdir -p "$OUT"
objs=""
generated=""

# Prefer top-level .xs: where they exist, any others (Class::XSAccessor's
# XS/*.xs) are pulled in via INCLUDE: and must not be compiled as translation
# units of their own. Where none exist, the dist keeps its XS in a subdirectory
# (Params::Validate::XS in lib/, Text::BibTeX in xscode/) and those are used.
xs_files=$(find . -maxdepth 1 -name '*.xs')
if [ -z "$xs_files" ]; then
    xs_files=$(find . -name '*.xs' -not -path './t/*')
fi
[ -n "$xs_files" ] || { echo "NO-XS $MOD"; exit 2; }

for xs in $xs_files; do
    # Absolute: ParseXS resolves a relative typemap against the .xs file's
    # directory, not the cwd, so Text::BibTeX's top-level typemap is invisible
    # from xscode/BibTeX.xs.
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

# Top-level .c, plus the .c siblings of each .xs: Text::BibTeX keeps
# btxs_support.c next to xscode/BibTeX.xs, and the generated .c lands there too.
c_files=$(find . -maxdepth 1 -name '*.c' -not -name 'conftest*')
for xs in $xs_files; do
    d=$(dirname "$xs")
    [ "$d" = "." ] && continue
    c_files="$c_files $(find "$d" -maxdepth 1 -name '*.c' -not -name 'conftest*')"
done
c_files=$(printf '%s\n' $c_files $generated | sort -u)

for c in $c_files; do
    o=${c%.c}.o
    emcc -c -O1 -I. -I"$CORE" $EXTRA \
        -DVERSION="\"$MODVER\"" -DXS_VERSION="\"$MODVER\"" \
        -o "$o" "$c" || { echo "CC-FAIL $MOD $c"; exit 3; }
    objs="$objs $o"
done

$AR rcs "$OUT/$LEAF.a" $objs || exit 4

# An archive with no members is the signature of an .xs that was never found;
# ar reports success and the failure only surfaces as a missing boot_ symbol at
# link time.
[ -n "$($AR t "$OUT/$LEAF.a")" ] || { echo "EMPTY-ARCHIVE $MOD"; exit 5; }
echo "OK $MOD -> $OUT/$LEAF.a"
