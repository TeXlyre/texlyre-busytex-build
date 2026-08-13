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
export PERL_WASM_PREFIX PERL_VERSION
export AR=${AR:-llvm-ar}

mkdir -p "$BUILD" "$DEPS_PREFIX"

SRCDIR=$SRCDIR PERL_VERSION=$PERL_VERSION bash "$ROOT/fetch_sources.sh"

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

    # 'make perl' rather than 'make': the default target continues into the
    # utilities, which run ../perl - a JS file with no shebang or exec bit - and
    # nothing in biber needs corelist, perldoc or the rest. Serial only, the
    # generate_uudmap rule races with itself under -j.
    make perl
    install_perl_headers
}

# make install runs installperl with the target perl, which is not executable on
# the host, so the pieces build_xs.sh needs are copied directly: the module tree,
# the CORE headers and libperl.a.
install_perl_headers() {
    site=$PERL_WASM_PREFIX/lib/$PERL_VERSION
    rm -rf "$site"
    mkdir -p "$site/wasm/CORE"
    cp -r lib/. "$site/"
    cp ./*.h "$site/wasm/CORE/"
    cp libperl.a "$site/wasm/CORE/"
    chmod -R u+w "$site"
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
    # miniperl from the cross build, so xsubpp matches the target perl exactly.
    # It needs -I: its own @INC is just '.', which is why Config.pm is missing.
    export HOST_PERL="$HOST_PERL_BUILD/miniperl -I$PERL_SRC/lib"
    export HOST_TYPEMAP=$PERL_SRC/lib/ExtUtils/typemap

    # PerlIO::utf8_strict exports PerlIOBase_flush_linebuf, which collides with
    # the identically named symbol in perl's own PerlIO layer at link time.
    sed -i 's/\bPerlIOBase_flush_linebuf\b/utf8strict_flush_linebuf/g' \
        "$SRCDIR/PerlIO-utf8_strict/utf8_strict.xs"
    rm -f "$SRCDIR/PerlIO-utf8_strict/utf8_strict.c"

    # List::MoreUtils::XS generates LMUconfig.h from its Makefile.PL, which is
    # never otherwise run because the XS is built out of tree. Probed with the
    # host compiler; the header only records a few HAVE_ feature defines.
    ( cd "$SRCDIR/List-MoreUtils-XS" && [ -f LMUconfig.h ] || perl Makefile.PL >/dev/null )
    [ -f "$SRCDIR/List-MoreUtils-XS/LMUconfig.h" ] || { echo "LMUconfig.h not generated"; exit 1; }

    SOMBOK_SRC=$SRCDIR/Unicode-LineBreak/sombok
    [ -d "$SOMBOK_SRC/lib" ] || SOMBOK_SRC=$SRCDIR/sombok
    SOMBOK_SRC=$SOMBOK_SRC DEPS_PREFIX=$DEPS_PREFIX SRCDIR=$SRCDIR bash "$ROOT/build_deps.sh" sombok
    SRCDIR=$SRCDIR DEPS_PREFIX=$DEPS_PREFIX bash "$ROOT/build_deps.sh" libxml2

    grep -vE '^\s*(#|$)' "$ROOT/modules.txt" | while read -r mod ver extra; do
        dir=$SRCDIR/$(echo "$mod" | sed 's/::/-/g')
        case "${extra:-}" in
            btparse)
                SRCDIR=$SRCDIR DEPS_PREFIX=$DEPS_PREFIX bash "$ROOT/build_deps.sh" btparse "$dir"
                MODVER=$ver bash "$ROOT/build_xs.sh" "$dir" "$mod" "-I$dir/btparse/src"
                $AR r "$PERL_WASM_LIB/auto/Text/BibTeX/BibTeX.a" "$dir"/btparse/src/*.o
                ;;
            sombok)
                MODVER=$ver bash "$ROOT/build_xs.sh" "$dir" "$mod" "-I$DEPS_PREFIX/sombok/include"
                merge_archive "$PERL_WASM_LIB/auto/Unicode/LineBreak/LineBreak.a" \
                              "$DEPS_PREFIX/sombok/lib/libsombok.a" sombok_
                ;;
            libxml2)
                MODVER=$ver bash "$ROOT/build_xs.sh" "$dir" "$mod" "-I$DEPS_PREFIX/libxml2/include/libxml2"
                merge_archive "$PERL_WASM_LIB/auto/XML/LibXML/LibXML.a" \
                              "$DEPS_PREFIX/libxml2/lib/libxml2.a" xml2_
                ;;
            *)
                MODVER=$ver bash "$ROOT/build_xs.sh" "$dir" "$mod" "${extra:-}"
                ;;
        esac
    done
}

# Safety net for the same class of problem patches/07 fixes by hand: an
# extension that keeps a private copy of a core translation unit (ext/re does
# this with regcomp.c) only avoids a clash because dynamic loading lets its
# copy shadow the core one. Statically linked, wasm-ld rejects the duplicate
# definitions. Any symbol defined in both libperl.a and an extension archive is
# renamed inside the extension, which also rewrites that archive's own
# references to it.
dedupe_static_ext() {
    objcopy=$(dirname "$(command -v emcc)")/../bin/llvm-objcopy
    [ -x "$objcopy" ] || objcopy=$(command -v llvm-objcopy || true)
    [ -x "$objcopy" ] || { echo "no llvm-objcopy, skipping duplicate symbol check"; return 0; }

    core=$(mktemp)
    $AR t libperl.a >/dev/null 2>&1 || return 0
    "$objcopy" --version >/dev/null 2>&1 || return 0
    nm_tool=$(dirname "$objcopy")/llvm-nm
    "$nm_tool" --defined-only --extern-only libperl.a 2>/dev/null | awk '{print $NF}' | sort -u > "$core"

    for a in $(perl -ne "print \$1 if /^static_ext='(.*)'/" config.sh); do
        leaf=${a##*/}
        archive=lib/auto/$a/$leaf.a
        [ -f "$archive" ] || continue
        dups=$("$nm_tool" --defined-only --extern-only "$archive" 2>/dev/null | awk '{print $NF}' | sort -u | comm -12 - "$core")
        [ -n "$dups" ] || continue
        echo "renaming $(echo "$dups" | wc -l) duplicate symbol(s) in $archive"
        args=""
        for d in $dups; do
            args="$args --redefine-sym $d=perlext_$d"
        done
        "$objcopy" $args "$archive"
    done
    rm -f "$core"
}

link_biber() {
    cd "$PERL_SRC"
    exts=$(grep -vE '^\s*(#|$)' "$ROOT/modules.txt" | awk '{gsub(/::/,"/",$1); printf "%s ", $1}')
    perl -i -pe "s{^static_ext='(.*)'\$}{static_ext='\$1 $exts'}" config.sh

    # Drop any extension whose archive was not produced, so a perl version that
    # moves an extension to pure perl degrades instead of failing the link.
    kept=""
    for e in $(perl -ne "print \$1 if /^static_ext='(.*)'/" config.sh); do
        leaf=${e##*/}
        if [ -f "lib/auto/$e/$leaf.a" ]; then
            kept="$kept $e"
        else
            echo "skipping static ext $e: lib/auto/$e/$leaf.a not built"
        fi
    done
    perl -i -pe "s{^static_ext='.*'\$}{static_ext='$kept'}" config.sh

    ./Configure -S
    rm -f perlmain.c perlmain.o nodeperl_dev.js
    dedupe_static_ext
    make perl
    install_perl_headers
}

# The perl half of everything that goes in the preload filesystem.
#
# biber's pure-perl dependency closure comes from the distro package rather than
# from cpanm. Installing biber with apt pulls that whole closure into
# /usr/share/perl5 already resolved and mutually consistent, needs no network at
# build time, and cannot half-fail partway through the way an --installdeps run
# can. It is also the arrangement this build was actually proven against.
#
# Only /usr/share/perl5 is copied: the arch directory holds compiled .so files
# for the host, which are useless here and whose modules are supplied by the
# statically linked XS instead.
install_biber_tree() {
    site=$PERL_WASM_PREFIX/lib/site_perl/$PERL_VERSION
    mkdir -p "$site"

    [ -d /usr/share/perl5 ] || { echo "no /usr/share/perl5; install the biber package first"; exit 1; }
    [ -f /usr/share/perl5/Biber.pm ] || { echo "biber package not installed on the host"; exit 1; }
    rm -rf "$site"
    mkdir -p "$site"
    cp -r /usr/share/perl5/. "$site/"
    chmod -R u+w "$site"

    # Over the top of the distro copies: the .pm files from the same sources the
    # XS was built from, so the perl side and the linked bootstrap agree on
    # version. A mismatch here fails at runtime with "object version ... does not
    # match bootstrap parameter".
    grep -vE '^\s*(#|$)' "$ROOT/modules.txt" | while read -r mod ver extra; do
        dir=$SRCDIR/$(echo "$mod" | sed 's/::/-/g')
        [ -d "$dir/lib" ] && cp -r "$dir/lib/." "$site/"

        # Not exclusive: Clone and Text::CSV_XS have only a top-level .pm named
        # after the last component of the module, and XML::LibXML has both, with
        # LibXML.pm at the top and the sub-modules under lib/.
        leaf=${mod##*::}
        if [ -f "$dir/$leaf.pm" ]; then
            sub=$(echo "${mod%::*}" | sed 's/::/\//g')
            [ "$sub" = "$mod" ] && sub=.
            mkdir -p "$site/$sub"
            cp "$dir/$leaf.pm" "$site/$sub/"
        fi
    done

    # biber itself from the requested release, overriding whatever the distro
    # packaged, so BIBER_VERSION means what it says.
    cp -r "$SRCDIR/biber/lib/." "$site/"
    chmod -R u+w "$site"
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
cp -r "$PERL_WASM_PREFIX" "$BUILD/prefix" 2>/dev/null || true
echo "biber wasm module in $BUILD"
