# Copyright 2026 The Skia Authors
# Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.
#
# CMake build for the Skia library. See cmake/README.md for the full story.
#
# This build is additive: it does not patch, replace or interfere with the GN
# (BUILD.gn) and Bazel (BUILD.bazel) builds, and nothing here is read by them.
#
# Typical use: configure with bmake as the make program, then build through
# cmake, which drives bmake and passes the job count down itself.
#
#   cmake -S . -B out/llvm.arm64.release -G "Unix Makefiles" \
#         -DCMAKE_MAKE_PROGRAM=$(command -v bmake) -DCMAKE_BUILD_TYPE=Release
#   cmake --build out/llvm.arm64.release --parallel 8
#
# (cmake/build_skia_bmake.sh does exactly that.)

cmake_minimum_required(VERSION 3.18)

if(APPLE AND NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
  # gn/skia/BUILD.gn uses "-target arm64-apple-macos11" for arm64 builds.
  set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum supported macOS version")
endif()

project(skia LANGUAGES C CXX)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
  message(FATAL_ERROR "In-source builds are not supported. Use: cmake -S . -B <build dir>")
endif()

# GN: cflags += [ "-std=c++20" ], no_exceptions/no_rtti configs, -fPIC.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(SKIA_ROOT "${CMAKE_CURRENT_LIST_DIR}")
list(APPEND CMAKE_MODULE_PATH "${SKIA_ROOT}/cmake")

include(SkiaOptions)
include(SkiaPlatform)
include(SkiaSourceLists)
include(SkiaTargets)

message(STATUS "Skia CMake: build type ${CMAKE_BUILD_TYPE}, "
               "${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "Skia CMake: Ganesh=${SKIA_BUILD_GANESH} GL=${SKIA_BUILD_GL} "
               "Metal=${SKIA_BUILD_METAL} modules=${SKIA_BUILD_MODULES}")
message(STATUS "Skia CMake: artifacts in ${CMAKE_BINARY_DIR} "
               "(see skia-vars.cmake for the consumer link line)")
