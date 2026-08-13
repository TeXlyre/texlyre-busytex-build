#!/bin/bash
# The three external C libraries biber's XS dependencies link against. Every
# other CPAN XS module in the set is self-contained.
set -eu
SRCDIR=${SRCDIR:?set SRCDIR}
DEPS_PREFIX=${DEPS_PREFIX:?set DEPS_PREFIX}
AR=${AR:-llvm-ar}

freeze_autotools() {
    touch aclocal.m4 configure config.h.in 2>/dev/null || true
    find . -name 'Makefile.in' -exec touch {} +
}

build_libxml2() {
    cd "$SRCDIR"/libxml2
    [ -x ./configure ] || autoreconf -fi
    freeze_autotools
    emconfigure ./configure \
        --disable-shared --enable-static \
        --without-python --without-zlib --without-lzma --without-icu \
        --without-http --without-ftp --without-modules --without-threads \
        --prefix="$DEPS_PREFIX/libxml2"
    freeze_autotools
    emmake make
    emmake make install
}

build_sombok() {
    cd "${SOMBOK_SRC:-$SRCDIR/sombok}"
    sed -e 's/@PACKAGE_VERSION@/2.4.0/' \
        -e 's/@SOMBOK_UNICHAR_T_IS_WCHAR_T@/#undef SOMBOK_UNICHAR_T_IS_WCHAR_T/' \
        -e 's/@SOMBOK_UNICHAR_T_IS_UNSIGNED_INT@/#define SOMBOK_UNICHAR_T_IS_UNSIGNED_INT 1/' \
        -e 's/@SOMBOK_UNICHAR_T_IS_UNSIGNED_LONG@/#undef SOMBOK_UNICHAR_T_IS_UNSIGNED_LONG/' \
        -e 's/@SOMBOK_UNICHAR_T@/unsigned int/' \
        include/sombok.h.in > include/sombok.h
    printf '#define HAVE_STDLIB_H 1\n#define HAVE_STRING_H 1\n#define PACKAGE_VERSION "2.4.0"\n#define VERSION "2.4.0"\n' > include/config.h
    for f in lib/*.c; do
        emcc -c -O1 -Iinclude -DHAVE_CONFIG_H -o "${f%.c}.o" "$f"
    done
    mkdir -p "$DEPS_PREFIX/sombok/lib" "$DEPS_PREFIX/sombok/include"
    $AR rcs "$DEPS_PREFIX/sombok/lib/libsombok.a" lib/*.o
    cp include/sombok.h include/sombok_constants.h "$DEPS_PREFIX/sombok/include/"
}

build_btparse() {
    cd "$1"/btparse/src
    sed -e 's/#\[% ALLOCA_H %\]/#define HAVE_ALLOCA_H 1/' \
        -e 's/#\[% STRLCAT %\]/#define HAVE_STRLCAT 1/' \
        -e 's/#\[% VSNPRINTF %\]/#define HAVE_VSNPRINTF 1/' \
        -e 's/\[% PACKAGE %\]/"libbtparse"/g' \
        -e 's/\[% FPACKAGE %\]/"libbtparse 0.89"/' \
        -e 's/\[% VERSION %\]/"0.89"/' \
        bt_config.h.in > bt_config.h
    cp bt_config.h config.h
    for f in *.c; do
        emcc -c -O1 -I. -DHAVE_CONFIG_H -o "${f%.c}.o" "$f"
    done
}

case "${1:-all}" in
    libxml2) build_libxml2 ;;
    sombok)  build_sombok ;;
    btparse) build_btparse "$2" ;;
    all)     build_libxml2; build_sombok ;;
esac
