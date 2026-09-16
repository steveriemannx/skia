# Copyright 2026 The Skia Authors
# Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.
#
# Every knob of the CMake build. Names mirror the GN arg they correspond to so
# that a GN args.gn can be translated by hand; defaults are chosen for a desktop
# build that produces the libraries the "dui" project links against.

set(SKIA_PRESET "" CACHE STRING
    "Convenience bundle of the options below. Supported: \"\" (defaults) or
     \"dui-parity\" (reproduces the argument set the dui project builds Skia with:
     no image codecs, no PDF, no freetype/ICU).")

if(SKIA_PRESET STREQUAL "dui-parity")
  # Force the defaults of every option this preset pins, then let the options
  # below keep normal cache semantics so an explicit -D still wins on a re-run.
  foreach(_opt SKIA_USE_LIBPNG SKIA_USE_LIBJPEG_TURBO SKIA_USE_LIBWEBP
               SKIA_USE_ZLIB SKIA_USE_EXPAT SKIA_USE_FREETYPE SKIA_USE_HARFBUZZ
               SKIA_USE_ICU SKIA_BUILD_PDF)
    if(NOT DEFINED ${_opt})
      set(${_opt} OFF CACHE BOOL "Pinned by SKIA_PRESET=dui-parity")
    endif()
  endforeach()
elseif(NOT SKIA_PRESET STREQUAL "")
  message(FATAL_ERROR "Unknown SKIA_PRESET '${SKIA_PRESET}'")
endif()

# --- What to build ---------------------------------------------------------

option(SKIA_BUILD_GANESH "Build the Ganesh GPU backend (SK_GANESH)" ON)
option(SKIA_BUILD_GL "Build Ganesh's OpenGL backend (SK_GL)" ON)
option(SKIA_BUILD_METAL "Build Ganesh's Metal backend (SK_METAL, macOS/iOS only)" OFF)
option(SKIA_BUILD_GRAPHITE "Build the Graphite backend (SK_GRAPHITE)" OFF)
option(SKIA_BUILD_PDF "Build PDF support (SK_SUPPORT_PDF)" OFF)
option(SKIA_BUILD_MODULES "Build modules/svg, skottie, sksg, skshaper, jsonreader" ON)
option(SKIA_BUILD_SKCMS "Also emit a standalone libskcms.a (its objects always go into libskia.a)" ON)
option(SKIA_BUILD_SKRESOURCES "Also emit a standalone libskresources.a (its objects always go into libsvg.a and libskottie.a)" ON)
option(SKIA_BUILD_FONT_MGRS "Build the freetype-based font managers (directory/embedded/empty)" ON)
option(SKIA_BUILD_SMOKE_TEST "Build cmake/smoke_test/skia_smoke_test.cpp" ON)
option(SKIA_INSTALL "Add install() rules for the libraries and headers" OFF)

# --- Third party dependencies ---------------------------------------------

option(SKIA_USE_FREETYPE "Use the system freetype2 (pkg-config freetype2)" ON)
option(SKIA_USE_HARFBUZZ "Use the system harfbuzz (pkg-config harfbuzz)" ON)
option(SKIA_USE_ICU "Use the system ICU - required for full text shaping" ON)
option(SKIA_USE_FONTCONFIG "Use the system fontconfig (non-Apple platforms)" ON)
option(SKIA_USE_LIBPNG "Use the system libpng for PNG decode/encode" ON)
option(SKIA_USE_LIBJPEG_TURBO "Use the system libjpeg-turbo for JPEG decode/encode" ON)
option(SKIA_USE_LIBWEBP "Use the system libwebp for WebP decode/encode" ON)
option(SKIA_USE_ZLIB "Use the system zlib" ON)
option(SKIA_USE_EXPAT "Use the system expat for SkXMLParser (needed by modules/svg)" ON)
option(SKIA_USE_PERFETTO "Define SK_USE_PERFETTO" OFF)
option(SKIA_USE_X11 "Use GLX for the GL backend on Linux (otherwise GrGLMakeNativeInterface_none)" OFF)

# --- Behaviour -------------------------------------------------------------

option(SKIA_ENABLE_TRIVIAL_ABI "Define SK_TRIVIAL_ABI on the public API" OFF)
set(SKIA_CXX_STANDARD 20 CACHE STRING "C++ standard used to compile Skia")

# --- Validation ------------------------------------------------------------

if(SKIA_BUILD_METAL AND NOT APPLE)
  message(FATAL_ERROR "SKIA_BUILD_METAL requires an Apple platform")
endif()

if(SKIA_BUILD_GRAPHITE)
  # The graphite source lists are available (gn/graphite.gni) but its backends
  # need Vulkan/Dawn/Metal sources from third_party/externals, which this build
  # deliberately does not fetch. Fail loudly rather than link something broken.
  message(FATAL_ERROR
      "SKIA_BUILD_GRAPHITE is not wired up in this CMake build yet; graphite needs "
      "the third_party/externals backends that this build does not use")
endif()

if(SKIA_BUILD_GL AND NOT (APPLE OR UNIX))
  message(FATAL_ERROR "SKIA_BUILD_GL is only wired up for Apple and Unix platforms")
endif()

if(SKIA_BUILD_MODULES AND NOT SKIA_USE_EXPAT)
  # modules/svg is guarded by skia_use_expat in GN too; the CMake build follows
  # that and simply leaves the module out rather than failing.
  message(STATUS "SKIA_USE_EXPAT=OFF: modules/svg will not be built")
endif()

if((SKIA_USE_FREETYPE OR SKIA_USE_HARFBUZZ OR SKIA_USE_ICU) AND NOT UNIX AND NOT APPLE)
  message(STATUS "Note: system library lookups assume Homebrew (macOS) or ports (/usr/local) layouts")
endif()
