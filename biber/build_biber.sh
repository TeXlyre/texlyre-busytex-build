#!/bin/bash
# Builds biber as a standalone wasm module: a perl interpreter with every XS
# dependency statically linked, plus biber's pure-perl tree in the preload
# filesystem. It is deliberately not linked into busytex: it cannot share the
# web2c multiplexer's main(), it is ~8 MB, and almost no compilation needs it.
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD:?set BUILD}
SRCDIR=$BUILD/src
DEPS_PREFIX=$BUILD/deps
PERL_SRC=$SRCDIR/perl
HOST_PERL_BUILD=$BUILD/hostperl
PERL_VERSION=${PERL_VERSION:-5.38.2}
PERL_WASM_PREFIX=${PERL_WASM_PREFIX:-$BUILD/prefix}
export AR=${AR:-llvm-ar}

mkdir -p "$BUILD" "$DEPS_PREFIX"

SRCDIR=$SRCDIR PERL_VERSION=$PERL_VERSION sh "$ROOT/fetch_sources.sh"

apply_patches() {
    cd "$PERL_SRC"
    [ -f .patched ] && return 0
    for p in "$ROOT"/patches/*.patch; do
        patch -p1 -N --no-backup-if-mismatch < "$p"
    done
    touch .patched
}

# The cross build needs a miniperl and generate_uudmap of the same version built
# for the host, from a pristine tree. Perl < 5.32 miscompiles under gcc >= 13 at
# -O2 (miniperl segfaults in buildcustomize), so the host build is pinned to -O0.
build_host_perl() {
    [ -x "$HOST_PERL_BUILD/miniperl" ] && return 0
    mkdir -p "$HOST_PERL_BUILD"
    cd "$HOST_PERL_BUILD"
    sh "$PERL_SRC/Configure" -des -Dusedevel -Dmksymlinks -Doptimize=-O0
    make miniperl generate_uudmap
}

build_wasm_perl() {
    cd "$PERL_SRC"
    export EMCC_REAL=$(command -v emcc)
    mkdir -p "$BUILD/shim"
    cp "$ROOT/emcc_configure_shim.sh" "$BUILD/shim/emcc"
    chmod +x "$BUILD/shim/emcc"
    export PATH=$BUILD/shim:$PATH

    export EMPERL_HOSTPERLDIR=$HOST_PERL_BUILD
    export EMPERL_PREFIX=$PERL_WASM_PREFIX
    export EMPERL_STATIC_EXT="Storable Sys/Hostname Unicode/Collate"

    sh Configure -des -Dhintfile=emscripten
    sh "$ROOT/config_fixups.sh" config.sh
    ./Configure -S

    # Serial only: the generate_uudmap rule races with itself under -j.
    make
    make install
}

# XML::LibXML ships dom.c, xpath.c and friends whose object names collide with
# libxml2's own members; ar silently replaces same-named members and the link
# then fails on domXPathFind and perlDocumentFunction. Members are renamed on
# the way in.
merge_archive() {
    target=$1; library=$2; prefix=$3
    staging=$(mktemp -d)
    (cd "$staging" && $AR x "$library")
    for o in "$staging"/*.o; do
        mv "$o" "$(dirname "$o")/$prefix$(basename "$o")"
    done
    $AR r "$target" "$staging"/*.o
    rm -rf "$staging"
}

build_xs_modules() {
    export PERL_WASM_PREFIX
    export PERL_WASM_VERSION=$PERL_VERSION
    export PERL_WASM_LIB=$PERL_SRC/lib
    export HOST_PERL=$HOST_PERL_BUILD/miniperl

    # PerlIO::utf8_strict exports PerlIOBase_flush_linebuf, which collides with
    # the identically named symbol in perl's own PerlIO layer at link time.
    sed -i 's/\bPerlIOBase_flush_linebuf\b/utf8strict_flush_linebuf/g' \
        "$SRCDIR/PerlIO-utf8_strict/utf8_strict.xs"
    rm -f "$SRCDIR/PerlIO-utf8_strict/utf8_strict.c"

    SOMBOK_SRC=$SRCDIR/Unicode-LineBreak/sombok
    [ -d "$SOMBOK_SRC/lib" ] || SOMBOK_SRC=$SRCDIR/sombok
    SOMBOK_SRC=$SOMBOK_SRC DEPS_PREFIX=$DEPS_PREFIX SRCDIR=$SRCDIR sh "$ROOT/build_deps.sh" sombok
    SRCDIR=$SRCDIR DEPS_PREFIX=$DEPS_PREFIX sh "$ROOT/build_deps.sh" libxml2

    grep -vE '^\s*(#|$)' "$ROOT/modules.txt" | while read -r mod ver extra; do
        dir=$SRCDIR/$(echo "$mod" | tr ':' '-')
        case "${extra:-}" in
            btparse)
                SRCDIR=$SRCDIR DEPS_PREFIX=$DEPS_PREFIX sh "$ROOT/build_deps.sh" btparse "$dir"
                MODVER=$ver "$ROOT/build_xs.sh" "$dir" "$mod" "-I$dir/btparse/src"
                $AR r "$PERL_WASM_LIB/auto/Text/BibTeX/BibTeX.a" "$dir"/btparse/src/*.o
                ;;
            sombok)
                MODVER=$ver "$ROOT/build_xs.sh" "$dir" "$mod" "-I$DEPS_PREFIX/sombok/include"
                merge_archive "$PERL_WASM_LIB/auto/Unicode/LineBreak/LineBreak.a" \
                              "$DEPS_PREFIX/sombok/lib/libsombok.a" sombok_
                ;;
            libxml2)
                MODVER=$ver "$ROOT/build_xs.sh" "$dir" "$mod" "-I$DEPS_PREFIX/libxml2/include/libxml2"
                merge_archive "$PERL_WASM_LIB/auto/XML/LibXML/LibXML.a" \
                              "$DEPS_PREFIX/libxml2/lib/libxml2.a" xml2_
                ;;
            *)
                MODVER=$ver "$ROOT/build_xs.sh" "$dir" "$mod" "${extra:-}"
                ;;
        esac
    done
}

link_biber() {
    cd "$PERL_SRC"
    exts=$(grep -vE '^\s*(#|$)' "$ROOT/modules.txt" | awk '{gsub(/::/,"/",$1); printf "%s ", $1}')
    perl -i -pe "s{^static_ext='(.*)'\$}{static_ext='\$1 $exts'}" config.sh
    ./Configure -S
    rm -f perlmain.c perlmain.o nodeperl_dev.js
    make perl
}

# biber's pure-perl dependency tree. cpanm installs into the wasm prefix with
# the host perl; only .pm files matter, every XS dependency is already linked in.
install_biber_tree() {
    site=$PERL_WASM_PREFIX/lib/site_perl/$PERL_VERSION
    mkdir -p "$site"
    cpanm --notest --local-lib-contained "$BUILD/cpanlib" --installdeps "$SRCDIR/biber" || true
    cp -r "$BUILD/cpanlib/lib/perl5/"* "$site/" 2>/dev/null || true
    cp -r "$SRCDIR/biber/lib/"* "$site/"
    install -D -m 755 "$SRCDIR/biber/bin/biber" "$PERL_WASM_PREFIX/bin/biber"
}

apply_patches
build_host_perl
build_wasm_perl
build_xs_modules
link_biber
install_biber_tree

cp "$PERL_SRC/nodeperl_dev.js" "$BUILD/biber.js"
[ -f "$PERL_SRC/nodeperl_dev.wasm" ] && cp "$PERL_SRC/nodeperl_dev.wasm" "$BUILD/biber.wasm"
echo "biber wasm module in $BUILD"
