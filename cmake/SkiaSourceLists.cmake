# Copyright 2026 The Skia Authors
# Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.
#
# Source lists. Almost everything comes from the machine-generated gn/*.gni and
# modules/*/*.gni files, converted to CMake at configure time (see
# gen_sources_from_gni.py) so that upstream rolls and `make -C bazel generate_gni`
# never require touching this file. What is left here by hand is only what
# BUILD.gn itself adds by hand.

find_package(Python3 COMPONENTS Interpreter REQUIRED)

file(GLOB_RECURSE SKIA_GNI_FILES CONFIGURE_DEPENDS
     "${SKIA_ROOT}/gn/*.gni" "${SKIA_ROOT}/modules/*/*.gni")

set(SKIA_GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
set(SKIA_GENERATED_SOURCES "${SKIA_GENERATED_DIR}/skia_sources.cmake")

execute_process(
    COMMAND "${Python3_EXECUTABLE}" "${SKIA_ROOT}/cmake/gen_sources_from_gni.py"
            --root "${SKIA_ROOT}" --out "${SKIA_GENERATED_SOURCES}"
    RESULT_VARIABLE _skia_gni_result
    ERROR_VARIABLE _skia_gni_error)
if(NOT _skia_gni_result EQUAL 0)
  message(FATAL_ERROR "gen_sources_from_gni.py failed:\n${_skia_gni_error}")
endif()
include("${SKIA_GENERATED_SOURCES}")

set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
             ${SKIA_GNI_FILES} "${SKIA_ROOT}/cmake/gen_sources_from_gni.py")

# ---------------------------------------------------------------------------
# Sources BUILD.gn adds by hand rather than through a .gni list. Line numbers
# refer to BUILD.gn in this revision.
# ---------------------------------------------------------------------------

# BUILD.gn:2052-2060 - always part of :skia.
set(SKIA_EXTRA_SOURCES
    "${SKIA_ROOT}/src/android/SkAndroidFrameworkUtils.cpp"
    "${SKIA_ROOT}/src/codec/SkAndroidCodec.cpp"
    "${SKIA_ROOT}/src/codec/SkAndroidCodecAdapter.cpp"
    "${SKIA_ROOT}/src/codec/SkSampledCodec.cpp"
    "${SKIA_ROOT}/src/ports/SkDiscardableMemory_none.cpp"
    "${SKIA_ROOT}/src/ports/SkMemory_malloc.cpp"
    "${SKIA_ROOT}/src/sfnt/SkOTTable_name.cpp"
    "${SKIA_ROOT}/src/sfnt/SkOTUtils.cpp")

# BUILD.gn:1103-1111 - optional("jpeg_decode").
set(SKIA_JPEG_DECODE_SOURCES
    "${SKIA_ROOT}/src/codec/SkJpegCodec.cpp"
    "${SKIA_ROOT}/src/codec/SkJpegDecoderMgr.cpp"
    "${SKIA_ROOT}/src/codec/SkJpegMetadataDecoderImpl.cpp"
    "${SKIA_ROOT}/src/codec/SkJpegSourceMgr.cpp"
    "${SKIA_ROOT}/src/codec/SkJpegUtility.cpp")

# BUILD.gn:1313 (png_decode_libpng) and BUILD.gn:1873 (webp_decode).
set(SKIA_ICO_CODEC_SOURCES "${SKIA_ROOT}/src/codec/SkIcoCodec.cpp")
set(SKIA_WEBP_DECODE_SOURCES "${SKIA_ROOT}/src/codec/SkWebpCodec.cpp")

# BUILD.gn:990-1018 - GrGLMakeNativeInterface implementation per platform.
if(SKIA_PLATFORM_APPLE)
  set(SKIA_GL_NATIVE_SOURCES "${SKIA_ROOT}/src/gpu/ganesh/gl/mac/GrGLMakeNativeInterface_mac.cpp")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND SKIA_USE_X11)
  set(SKIA_GL_NATIVE_SOURCES "${SKIA_ROOT}/src/gpu/ganesh/gl/glx/GrGLMakeNativeInterface_glx.cpp")
else()
  set(SKIA_GL_NATIVE_SOURCES "${SKIA_ROOT}/src/gpu/ganesh/gl/GrGLMakeNativeInterface_none.cpp")
endif()

# BUILD.gn:2094-2100, 2124-2125, 2131-2134 - per platform ports files.
set(SKIA_PLATFORM_PORT_SOURCES "")
if(SKIA_PLATFORM_APPLE)
  list(APPEND SKIA_PLATFORM_PORT_SOURCES
       "${SKIA_ROOT}/src/ports/SkOSFile_posix.cpp"   # BUILD.gn:2104 (the non-win branch)
       "${SKIA_ROOT}/src/ports/SkImageGeneratorCG.cpp"
       "${SKIA_ROOT}/src/ports/SkLog_stdio.cpp")
else()
  list(APPEND SKIA_PLATFORM_PORT_SOURCES
       "${SKIA_ROOT}/src/ports/SkOSFile_posix.cpp"
       "${SKIA_ROOT}/src/ports/SkLog_stdio.cpp")
endif()

# SkCLZ/SkOpts per-architecture sources (gn/opts.gni keys "ml3"/"ml4"/"lasx").
set(SKIA_ARCH_OPT_SOURCES "")
if(SKIA_ARCH_X86_64)
  set(SKIA_ARCH_OPT_SOURCES
      "${SKIA_ROOT}/src/opts/SkOpts_ml3.cpp"
      "${SKIA_ROOT}/src/opts/SkOpts_ml4.cpp")
elseif(SKIA_ARCH_LOONG64)
  set(SKIA_ARCH_OPT_SOURCES "${SKIA_ROOT}/src/opts/SkOpts_lasx.cpp")
endif()

# modules/skcms - its own static_library in GN (modules/skcms/BUILD.gn).
set(SKIA_SKCMS_SOURCES "${SKIA_ROOT}/modules/skcms/skcms.cc"
                       "${SKIA_ROOT}/modules/skcms/src/skcms_TransformBaseline.cc")
if(SKIA_ARCH_X86_64)
  list(APPEND SKIA_SKCMS_SOURCES
       "${SKIA_ROOT}/modules/skcms/src/skcms_TransformHsw.cc"
       "${SKIA_ROOT}/modules/skcms/src/skcms_TransformSkx.cc")
endif()
