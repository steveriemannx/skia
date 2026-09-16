# Copyright 2026 The Skia Authors
# Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.
#
# Platform detection, system dependency discovery and the compile options /
# defines that GN's configs would otherwise supply. Mirrors, where it matters,
# gn/skia/BUILD.gn (config("default")) and BUILD.gn (:skia_public, :skia_private).

if(APPLE)
  set(SKIA_PLATFORM_APPLE ON)
  message(STATUS "Skia CMake: Apple platform, deployment target ${CMAKE_OSX_DEPLOYMENT_TARGET}")
elseif(UNIX)
  set(SKIA_PLATFORM_UNIX ON)
  message(STATUS "Skia CMake: ${CMAKE_SYSTEM_NAME} platform, processor ${CMAKE_SYSTEM_PROCESSOR}")
else()
  message(FATAL_ERROR "This CMake build currently supports Apple and Unix (Linux/FreeBSD) only")
endif()

# Architecture the per-file flags below key off.
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|x64")
  set(SKIA_ARCH_X86_64 ON)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
  set(SKIA_ARCH_ARM64 ON)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "loongarch64")
  set(SKIA_ARCH_LOONG64 ON)
endif()

set(SKIA_PUBLIC_DEFINES
    # Always present: the BMP/WBMP decoders are part of :skia with no external dep.
    SK_CODEC_DECODES_BMP
    SK_CODEC_DECODES_WBMP)
set(SKIA_PRIVATE_DEFINES
    SKIA_IMPLEMENTATION=1
    SK_GAMMA_APPLY_TO_A8)
set(SKIA_SYSTEM_LIBS "")

# --------------------------------------------------------------------------
# Optional features (each mirrors the GN optional() target of the same name).
# --------------------------------------------------------------------------

if(SKIA_BUILD_GANESH)
  list(APPEND SKIA_PUBLIC_DEFINES SK_GANESH)
endif()
if(SKIA_BUILD_GRAPHITE)
  list(APPEND SKIA_PUBLIC_DEFINES SK_GRAPHITE SK_ENABLE_PRECOMPILE)
endif()
if(SKIA_BUILD_PDF)
  list(APPEND SKIA_PUBLIC_DEFINES SK_SUPPORT_PDF)
endif()
if(SKIA_USE_PERFETTO)
  list(APPEND SKIA_PUBLIC_DEFINES SK_USE_PERFETTO)
endif()
if(SKIA_ENABLE_TRIVIAL_ABI)
  list(APPEND SKIA_PUBLIC_DEFINES SK_TRIVIAL_ABI)
endif()
if(SKIA_ARCH_X86_64)
  # GN sets this unconditionally in :skia_private; on non-x86 it is inert.
  list(APPEND SKIA_PRIVATE_DEFINES SK_ENABLE_AVX512_OPTS)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  # Public: consumers must agree (include/core/SkTypes.h).
  list(APPEND SKIA_PUBLIC_DEFINES SK_R32_SHIFT=16)
endif()

# --- libpng ---------------------------------------------------------------
if(SKIA_USE_LIBPNG)
  find_package(PNG REQUIRED)
  list(APPEND SKIA_SYSTEM_LIBS PNG::PNG)
  list(APPEND SKIA_PUBLIC_DEFINES
       SK_CODEC_DECODES_ICO
       SK_CODEC_DECODES_PNG
       SK_CODEC_DECODES_PNG_WITH_LIBPNG
       SK_CODEC_ENCODES_PNG
       SK_CODEC_ENCODES_PNG_WITH_LIBPNG)
  set(SKIA_HAVE_LIBPNG ON)
endif()

# --- libjpeg-turbo --------------------------------------------------------
if(SKIA_USE_LIBJPEG_TURBO)
  find_package(JPEG REQUIRED)
  list(APPEND SKIA_SYSTEM_LIBS JPEG::JPEG)
  list(APPEND SKIA_PUBLIC_DEFINES SK_CODEC_DECODES_JPEG SK_CODEC_ENCODES_JPEG)
  set(SKIA_HAVE_JPEG ON)
endif()

# --- libwebp --------------------------------------------------------------
if(SKIA_USE_LIBWEBP)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(WEBP REQUIRED IMPORTED_TARGET libwebp)
  pkg_check_modules(WEBPDEMUX REQUIRED IMPORTED_TARGET libwebpdemux)
  pkg_check_modules(WEBPMUX REQUIRED IMPORTED_TARGET libwebpmux)
  list(APPEND SKIA_SYSTEM_LIBS PkgConfig::WEBP PkgConfig::WEBPDEMUX PkgConfig::WEBPMUX)
  list(APPEND SKIA_PUBLIC_DEFINES SK_CODEC_DECODES_WEBP SK_CODEC_ENCODES_WEBP)
  set(SKIA_HAVE_WEBP ON)
endif()

# --- zlib / expat (both ship with the macOS SDK and with every Unix) ------
if(SKIA_USE_ZLIB)
  find_package(ZLIB REQUIRED)
  list(APPEND SKIA_SYSTEM_LIBS ZLIB::ZLIB)
  set(SKIA_HAVE_ZLIB ON)
endif()

if(SKIA_USE_EXPAT)
  find_package(EXPAT REQUIRED)
  list(APPEND SKIA_SYSTEM_LIBS EXPAT::EXPAT)
  list(APPEND SKIA_PUBLIC_DEFINES SK_XML)
  set(SKIA_HAVE_EXPAT ON)
endif()

# --- freetype / harfbuzz / ICU -------------------------------------------
if(SKIA_USE_FREETYPE OR SKIA_USE_HARFBUZZ)
  find_package(PkgConfig REQUIRED)
endif()

if(SKIA_USE_FREETYPE)
  pkg_check_modules(FREETYPE2 REQUIRED IMPORTED_TARGET freetype2)
  list(APPEND SKIA_SYSTEM_LIBS PkgConfig::FREETYPE2)
  list(APPEND SKIA_PUBLIC_DEFINES
       SK_TYPEFACE_FACTORY_FREETYPE
       SK_FONTMGR_FREETYPE_EMPTY_AVAILABLE
       SK_FONTMGR_FREETYPE_DIRECTORY_AVAILABLE
       SK_FONTMGR_FREETYPE_EMBEDDED_AVAILABLE)
  set(SKIA_HAVE_FREETYPE ON)
endif()

if(SKIA_USE_HARFBUZZ)
  pkg_check_modules(HARFBUZZ REQUIRED IMPORTED_TARGET harfbuzz)
  list(APPEND SKIA_SYSTEM_LIBS PkgConfig::HARFBUZZ)
  list(APPEND SKIA_PUBLIC_DEFINES SK_SHAPER_HARFBUZZ_AVAILABLE)
  set(SKIA_HAVE_HARFBUZZ ON)
endif()

if(SKIA_USE_ICU)
  # Homebrew keeps ICU keg-only, so point FindICU at the versioned prefix.
  foreach(_prefix /opt/homebrew/opt/icu4c /usr/local/opt/icu4c /usr/local)
    if(EXISTS "${_prefix}/include/unicode/utypes.h")
      list(APPEND ICU_ROOT "${_prefix}")
    endif()
  endforeach()
  find_package(ICU REQUIRED COMPONENTS uc i18n)
  list(APPEND SKIA_SYSTEM_LIBS ICU::uc ICU::i18n)
  list(APPEND SKIA_PUBLIC_DEFINES SK_UNICODE_AVAILABLE SK_UNICODE_ICU_IMPLEMENTATION)
  set(SKIA_HAVE_ICU ON)
endif()

# --- threads / platform libraries and frameworks --------------------------
find_package(Threads REQUIRED)
list(APPEND SKIA_SYSTEM_LIBS Threads::Threads)

if(SKIA_PLATFORM_APPLE)
  list(APPEND SKIA_PUBLIC_DEFINES
       SK_TYPEFACE_FACTORY_CORETEXT
       SK_FONTMGR_CORETEXT_AVAILABLE)
  list(APPEND SKIA_SYSTEM_LIBS
       "-framework ApplicationServices"
       "-framework AppKit"
       "-framework CoreFoundation"
       "-framework CoreGraphics"
       "-framework CoreText")
  if(SKIA_BUILD_METAL)
    list(APPEND SKIA_SYSTEM_LIBS "-framework Metal" "-framework Foundation")
  endif()
else()
  if(SKIA_USE_FONTCONFIG)
    find_package(Fontconfig REQUIRED)
    list(APPEND SKIA_SYSTEM_LIBS Fontconfig::Fontconfig)
    list(APPEND SKIA_PUBLIC_DEFINES SK_FONTMGR_FONTCONFIG_AVAILABLE)
    set(SKIA_HAVE_FONTCONFIG ON)
  endif()
  list(APPEND SKIA_SYSTEM_LIBS ${CMAKE_DL_LIBS})
endif()

# --------------------------------------------------------------------------
# Compile options (gn/skia/BUILD.gn config("default") + no_exceptions/no_rtti).
# --------------------------------------------------------------------------
function(skia_apply_compile_options target)
  set(_cxx_flags
      -Wno-attributes
      -ffp-contract=off
      -fstrict-aliasing
      -fvisibility=hidden
      -fvisibility-inlines-hidden
      -fno-exceptions
      -fno-rtti)
  target_compile_options(${target} PRIVATE
      $<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:${_cxx_flags}>)
  if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(${target} PRIVATE
        $<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-g -gdwarf-4>)
  else()
    # GN's is_official_build, which is what the shipped releases use.
    target_compile_definitions(${target} PRIVATE SK_DISABLE_TRACING)
  endif()
endfunction()

# --------------------------------------------------------------------------
# Plain "-l<name>" / "-L<dir>" equivalents of the dependencies above, for
# consumers that do not want to re-run find_package/pkg-config themselves
# (exported through skia-vars.cmake).
# --------------------------------------------------------------------------
set(SKIA_DEP_LIB_NAMES "")
set(SKIA_DEP_LIB_DIRS "")

function(skia_note_dep_library name)
  list(APPEND SKIA_DEP_LIB_NAMES ${name})
  foreach(_path ${ARGN})
    if(_path MATCHES "^/.*\\.(a|dylib|so|tbd)")
      get_filename_component(_dir "${_path}" DIRECTORY)
      list(APPEND SKIA_DEP_LIB_DIRS "${_dir}")
    elseif(_path MATCHES "^/")
      list(APPEND SKIA_DEP_LIB_DIRS "${_path}")
    endif()
  endforeach()
  set(SKIA_DEP_LIB_NAMES "${SKIA_DEP_LIB_NAMES}" PARENT_SCOPE)
  list(REMOVE_DUPLICATES SKIA_DEP_LIB_DIRS)
  set(SKIA_DEP_LIB_DIRS "${SKIA_DEP_LIB_DIRS}" PARENT_SCOPE)
endfunction()

if(SKIA_HAVE_LIBPNG)
  skia_note_dep_library(png "${PNG_LIBRARY}")
endif()
if(SKIA_HAVE_JPEG)
  skia_note_dep_library(jpeg "${JPEG_LIBRARY}")
endif()
if(SKIA_HAVE_WEBP)
  skia_note_dep_library(webp ${WEBP_LIBRARY_DIRS})
  skia_note_dep_library(webpdemux ${WEBPDEMUX_LIBRARY_DIRS})
  skia_note_dep_library(webpmux ${WEBPMUX_LIBRARY_DIRS})
endif()
if(SKIA_HAVE_ZLIB)
  skia_note_dep_library(z "${ZLIB_LIBRARY}")
endif()
if(SKIA_HAVE_EXPAT)
  skia_note_dep_library(expat "${EXPAT_LIBRARY}")
endif()
if(SKIA_HAVE_FREETYPE)
  skia_note_dep_library(freetype ${FREETYPE2_LIBRARY_DIRS})
endif()
if(SKIA_HAVE_HARFBUZZ)
  skia_note_dep_library(harfbuzz ${HARFBUZZ_LIBRARY_DIRS})
endif()
if(SKIA_HAVE_ICU)
  skia_note_dep_library(icuuc "${ICU_UC_LIBRARY}")
  skia_note_dep_library(icui18n "${ICU_I18N_LIBRARY}")
  skia_note_dep_library(icudata "${ICU_DATA_LIBRARY}")
endif()
if(NOT SKIA_PLATFORM_APPLE)
  list(APPEND SKIA_DEP_LIB_NAMES pthread dl)
endif()

# Aggregate a set of SKIA_GN_* lists into target sources, rooted at SKIA_ROOT.
function(skia_gni_sources out_var)
  set(_result "")
  foreach(_list ${ARGN})
    if(NOT DEFINED SKIA_GN_${_list})
      message(FATAL_ERROR "gn list '${_list}' was not produced by cmake/gen_sources_from_gni.py; "
                          "run it with --check to see what the .gni files define")
    endif()
    foreach(_src ${SKIA_GN_${_list}})
      list(APPEND _result "${SKIA_ROOT}/${_src}")
    endforeach()
  endforeach()
  set(${out_var} "${${out_var}};${_result}" PARENT_SCOPE)
endfunction()
