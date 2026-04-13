#!/bin/bash
set -e

NATIVE_RELEASE="build_native_ff0318af379bd80fb72b9b928d4744b5d9c9077d_12853073565_1"
URLRELEASE="https://github.com/busytex/busytex/releases/download/${NATIVE_RELEASE}"
EMSCRIPTEN_VERSION="3.1.43"

# Parse arguments
BUILD_TARGET="${1:-wasm-all}"

# Clean build artifacts that may have macOS-specific symlinks (only if clean requested)
if [ "$1" = "clean" ]; then
  rm -rf build source
  exit 0
fi

podman run --rm -v "$(pwd):/work" -w /work emscripten/emsdk:${EMSCRIPTEN_VERSION} bash -c "
  sudo apt-get update &&
  sudo apt-get install -y gperf p7zip-full icu-devtools file &&
  make URLRELEASE=${URLRELEASE} download-native &&
  make source/texlive.txt &&
  make ${BUILD_TARGET}
"
