#!/bin/bash
# Fetches every source the biber wasm build needs into $SRCDIR.
#
# CPAN dists are resolved through fastapi.metacpan.org so no author ids are
# pinned; this is the same trick build-biber.yml already uses. Nothing is taken
# from apt-get source, which needs deb-src enabled and is unavailable on the
# GitHub runner images by default.
set -eu
set -o pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
SRCDIR=${SRCDIR:?set SRCDIR}
PERL_VERSION=${PERL_VERSION:-5.38.2}
BIBER_VERSION=${BIBER_VERSION:-2.19}
LIBXML2_VERSION=${LIBXML2_VERSION:-2.9.14}
SOMBOK_REPO=${SOMBOK_REPO:-https://github.com/hatukanezumi/sombok.git}
EMPERL_REPO=${EMPERL_REPO:-https://github.com/haukex/emperl5.git}
EMPERL_BRANCH=${EMPERL_BRANCH:-emperl_v5.30.0}

mkdir -p "$SRCDIR"

# Module::Name -> Module-Name. tr ':' '-' would double every dash.
dist_dir() {
    echo "$1" | sed 's/::/-/g'
}

# curl -sL happily emits a 404 body, which then reaches tar as "not in gzip
# format" with no indication of which download failed.
fetch_tar() {
    url=$1; dest=$2; flag=$3
    mkdir -p "$dest"
    if ! curl -fsSL "$url" | tar -x$flag -f - --strip-components=1 --directory="$dest"; then
        echo "failed to fetch $url"
        rm -rf "$dest"
        return 1
    fi
}

fetch_cpan() {
    module=$1; version=$2
    dest="$SRCDIR/$(dist_dir "$module")"
    [ -d "$dest" ] && return 0
    url=$(curl -sL "https://fastapi.metacpan.org/v1/download_url/$module?version===$version" \
          | grep -o '"download_url"[^,]*' | cut -d'"' -f4)
    [ -n "$url" ] || { echo "cannot resolve $module $version on metacpan"; exit 1; }
    fetch_tar "$url" "$dest" z
    echo "fetched $module $version"
}

grep -vE '^\s*(#|$)' "$ROOT/modules.txt" | while read -r module version extra; do
    fetch_cpan "$module" "$version"
done

# biber itself
if [ ! -d "$SRCDIR/biber" ]; then
    fetch_tar "https://codeload.github.com/plk/biber/tar.gz/refs/tags/v$BIBER_VERSION" "$SRCDIR/biber" z
fi

# biber's pure-perl dependency tree, installed into the wasm prefix later
if [ ! -f "$SRCDIR/cpanfile" ]; then
    cp "$SRCDIR/biber/Build.PL" "$SRCDIR/cpanfile" 2>/dev/null || true
fi

# perl, patched for emscripten. The emperl branch is the upstream reference for
# the patch series; the tree actually built is pristine perl $PERL_VERSION with
# patches/ applied, because emperl's newest branch is 5.30.0 and biber's
# Build.PL requires 5.32.0.
if [ ! -d "$SRCDIR/perl" ]; then
    fetch_tar "https://www.cpan.org/src/5.0/perl-$PERL_VERSION.tar.gz" "$SRCDIR/perl" z
fi

# emperl supplies ext/WebPerl, nodeperl_dev_prerun.js and the nodeperl_dev
# launcher, which the patch series references but does not contain.
if [ ! -d "$SRCDIR/emperl" ]; then
    git clone --depth 1 -b "$EMPERL_BRANCH" "$EMPERL_REPO" "$SRCDIR/emperl"
fi
for f in nodeperl_dev_prerun.js nodeperl_dev; do
    [ -f "$SRCDIR/emperl/$f" ] && cp "$SRCDIR/emperl/$f" "$SRCDIR/perl/"
done
[ -d "$SRCDIR/emperl/ext/WebPerl" ] && cp -r "$SRCDIR/emperl/ext/WebPerl" "$SRCDIR/perl/ext/"

# libxml2
if [ ! -d "$SRCDIR/libxml2" ]; then
    series=${LIBXML2_VERSION%.*}
    # The GNOME release tarball carries a generated configure; the GitHub mirror
    # does not, so the fallback path runs autoreconf in build_deps.sh.
    if ! fetch_tar "https://download.gnome.org/sources/libxml2/$series/libxml2-$LIBXML2_VERSION.tar.xz" "$SRCDIR/libxml2" J; then
        fetch_tar "https://codeload.github.com/GNOME/libxml2/tar.gz/refs/tags/v$LIBXML2_VERSION" "$SRCDIR/libxml2" z
    fi
fi

# sombok. The CPAN Unicode-LineBreak dist references a bundled copy but does not
# ship one, so it is cloned from upstream. There is no 2.4.0 tag - the only tags
# are the old sombok-2011.x REL1 series - and master carries VERSION 2.4.0, which
# is what the XS expects. The tree is hand-configured in build_deps.sh, so the
# missing autotools output does not matter.
if [ ! -d "$SRCDIR/Unicode-LineBreak/sombok/lib" ] && [ ! -d "$SRCDIR/sombok" ]; then
    git clone --depth 1 "$SOMBOK_REPO" "$SRCDIR/sombok"
    test -f "$SRCDIR/sombok/include/sombok.h.in" || { echo "unexpected sombok layout"; exit 1; }
fi

echo "sources ready in $SRCDIR"
