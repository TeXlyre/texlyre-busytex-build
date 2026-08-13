#!/bin/bash
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

fetch_tar() {
    url=$1; dest=$2; flag=$3
    mkdir -p "$dest"
    if ! curl -fsSL "$url" | tar -x"$flag" -f - --strip-components=1 --directory="$dest"; then
        echo "failed to fetch $url"
        rm -rf "$dest"
        return 1
    fi
}

fetch_cpan() {
    module=$1; version=$2
    dest="$SRCDIR/$(echo "$module" | sed 's/::/-/g')"
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

[ -d "$SRCDIR/biber" ] || \
    fetch_tar "https://codeload.github.com/plk/biber/tar.gz/refs/tags/v$BIBER_VERSION" "$SRCDIR/biber" z

[ -d "$SRCDIR/perl" ] || \
    fetch_tar "https://www.cpan.org/src/5.0/perl-$PERL_VERSION.tar.gz" "$SRCDIR/perl" z

if [ ! -d "$SRCDIR/emperl" ]; then
    git clone --depth 1 -b "$EMPERL_BRANCH" "$EMPERL_REPO" "$SRCDIR/emperl"
fi
for f in nodeperl_dev_prerun.js nodeperl_dev; do
    [ -f "$SRCDIR/emperl/$f" ] && cp "$SRCDIR/emperl/$f" "$SRCDIR/perl/"
done
[ -d "$SRCDIR/emperl/ext/WebPerl" ] && cp -r "$SRCDIR/emperl/ext/WebPerl" "$SRCDIR/perl/ext/"

# The GNOME release tarball carries a generated configure; the GitHub mirror
# does not, and build_deps.sh runs autoreconf in that case.
if [ ! -d "$SRCDIR/libxml2" ]; then
    series=${LIBXML2_VERSION%.*}
    fetch_tar "https://download.gnome.org/sources/libxml2/$series/libxml2-$LIBXML2_VERSION.tar.xz" "$SRCDIR/libxml2" J \
        || fetch_tar "https://codeload.github.com/GNOME/libxml2/tar.gz/refs/tags/v$LIBXML2_VERSION" "$SRCDIR/libxml2" z
fi

# Upstream has no 2.4.0 tag; master carries VERSION 2.4.0, which is what the XS
# expects, and the tree is hand-configured in build_deps.sh anyway.
if [ ! -d "$SRCDIR/Unicode-LineBreak/sombok/lib" ] && [ ! -d "$SRCDIR/sombok" ]; then
    git clone --depth 1 "$SOMBOK_REPO" "$SRCDIR/sombok"
    test -f "$SRCDIR/sombok/include/sombok.h.in" || { echo "unexpected sombok layout"; exit 1; }
fi

echo "sources ready in $SRCDIR"
