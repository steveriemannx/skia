#!/usr/bin/env bash
# Copyright 2026 The Skia Authors
# Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.
#
# Configure Skia with CMake (using bmake, NetBSD make, as the make program) and
# build it with "cmake --build". bmake is never invoked by hand: cmake drives it
# and passes the job count itself, which is what keeps the recursive builds of
# the generated makefiles in order.
#
#   cmake/build_skia_bmake.sh                       # Release, host arch
#   cmake/build_skia_bmake.sh Debug
#   BMAKE=/usr/bin/bmake JOBS=4 cmake/build_skia_bmake.sh Release -DSKIA_BUILD_METAL=ON
#   JOBS=1 cmake/build_skia_bmake.sh                # serial, if -j ever stalls
#
# Artifacts land in <skia>/out/llvm.<arch>.<buildtype>/, which is where the dui
# project looks for a prebuilt Skia (see cmake/README.md).

set -euo pipefail

SKIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_TYPE="${1:-Release}"
shift || true

ARCH="${SKIA_ARCH:-$(uname -m)}"
BUILD_DIR="${SKIA_BUILD_DIR:-${SKIA_DIR}/out/llvm.${ARCH}.$(echo "${BUILD_TYPE}" | tr '[:upper:]' '[:lower:]')}"

if [[ -z "${BMAKE:-}" ]]; then
  BMAKE="$(command -v bmake || true)"
fi
if [[ -z "${BMAKE}" ]]; then
  echo "bmake not found. Install it with: brew install bmake (macOS) or pkg install bmake (FreeBSD)" >&2
  exit 1
fi

if [[ -z "${JOBS:-}" ]]; then
  JOBS="$( (sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4) )"
fi

echo "Skia:      ${SKIA_DIR}"
echo "Build dir: ${BUILD_DIR}"
echo "Make:      ${BMAKE} (driven by cmake --build, ${JOBS} jobs)"
echo

cmake -S "${SKIA_DIR}" -B "${BUILD_DIR}" \
      -G "Unix Makefiles" \
      -DCMAKE_MAKE_PROGRAM="${BMAKE}" \
      -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
      "$@"

# Let cmake drive bmake: it passes the job count down (JOBS=1 for a serial
# build) and keeps the reconfigure check of the recursive makefiles in order.
cmake --build "${BUILD_DIR}" --parallel "${JOBS}"

echo
echo "Libraries:"
ls -1 "${BUILD_DIR}"/*.a
echo
echo "Run ${BUILD_DIR}/skia_smoke_test to check the build end to end."
