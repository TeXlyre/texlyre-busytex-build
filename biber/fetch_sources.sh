#!/bin/bash
# Fetches every source the biber wasm build needs into $SRCDIR.
#
# CPAN dists are resolved through fastapi.metacpan.org so no author ids are
# pinned; this is the same trick build-biber.yml already uses. Nothing is taken
# from apt-get source, which needs deb-src enabled and is unavailable on the
# GitHub runner images by default.
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
SRCDIR=${SRCDIR:?set SRCDIR}
PERL_VERSION=${PERL_VERSION:-5.38.2}
BIBER_VERSION=${BIBER_VERSION:-2.19}
LIBXML2_VERSION=${LIBXML2_VERSION:-2.9.14}
SOMBOK_VERSION=${SOMBOK_VERSION:-2.4.0}
EMPERL_REPO=${EMPERL_REPO:-https://github.com/haukex/emperl5.git}
EMPERL_BRANCH=${EMPERL_BRANCH:-emperl_v5.30.0}

mkdir -p "$SRCDIR"

fetch_cpan() {
    module=$1; version=$2
    dest="$SRCDIR/$(echo "$module" | tr ':' '-')"
    [ -d "$dest" ] && return 0
    url=$(curl -sL "https://fastapi.metacpan.org/v1/download_url/$module?version===$version" \
          | grep -o '"download_url"[^,]*' | cut -d'"' -f4)
    [ -n "$url" ] || { echo "cannot resolve $module $version on metacpan"; exit 1; }
    mkdir -p "$dest"
    curl -sL "$url" | tar -xzf - --strip-components=1 --directory="$dest"
    echo "fetched $module $version"
}

grep -vE '^\s*(#|$)' "$ROOT/modules.txt" | while read -r module version extra; do
    fetch_cpan "$module" "$version"
done

# biber itself
if [ ! -d "$SRCDIR/biber" ]; then
    mkdir -p "$SRCDIR/biber"
    curl -sL "https://codeload.github.com/plk/biber/tar.gz/refs/tags/v$BIBER_VERSION" \
        | tar -xzf - --strip-components=1 --directory="$SRCDIR/biber"
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
    mkdir -p "$SRCDIR/perl"
    curl -sL "https://www.cpan.org/src/5.0/perl-$PERL_VERSION.tar.gz" \
        | tar -xzf - --strip-components=1 --directory="$SRCDIR/perl"
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
    mkdir -p "$SRCDIR/libxml2"
    series=${LIBXML2_VERSION%.*}
    curl -sL "https://download.gnome.org/sources/libxml2/$series/libxml2-$LIBXML2_VERSION.tar.xz" \
        | tar -xJf - --strip-components=1 --directory="$SRCDIR/libxml2"
fi

# sombok. The CPAN Unicode-LineBreak dist normally bundles it; the tarball is
# only fetched when that bundled copy is absent.
if [ ! -d "$SRCDIR/Unicode-LineBreak/sombok/lib" ] && [ ! -d "$SRCDIR/sombok" ]; then
    mkdir -p "$SRCDIR/sombok"
    curl -sL "https://github.com/hatukanezumi/sombok/releases/download/$SOMBOK_VERSION/sombok-$SOMBOK_VERSION.tar.gz" \
        | tar -xzf - --strip-components=1 --directory="$SRCDIR/sombok"
fi

echo "sources ready in $SRCDIR"
