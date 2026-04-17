#!/bin/bash
set -e

NATIVE_RELEASE="build_native_25cb7a9ae6f588003d82857b956e4965bea9a753_24562298930_1"
URLRELEASE="https://github.com/busytex/busytex/releases/download/${NATIVE_RELEASE}"
EMSCRIPTEN_VERSION="5.0.4"

# Parse arguments
BUILD_TARGET="${1:-wasm-all}"

if [ "$1" = "clean" ]; then
  rm -rf build source
  exit 0
fi

podman run --rm -v "$(pwd):/work" -w /work emscripten/emsdk:${EMSCRIPTEN_VERSION} bash -c "
  sudo apt-get update &&
  sudo apt-get install -y gperf p7zip-full icu-devtools libarchive-tools libnsl-dev dos2unix bubblewrap texlive-binaries file &&
  make URLRELEASE=${URLRELEASE} download-native &&
  make source/texlive.txt &&
  make ${BUILD_TARGET}
"