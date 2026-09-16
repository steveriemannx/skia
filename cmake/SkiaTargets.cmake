# Copyright 2026 The Skia Authors
# Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.
#
# The target graph. It follows BUILD.gn's :core/:skia/:gpu targets and the
# modules' own targets, with two deliberate simplifications:
#
#  1. GN builds with complete_static_library, so every "component" carries its
#     own copy of the core objects (libsvg.a literally contains 266 core.*
#     objects again). We compile each source once instead. Consumers must keep
#     the link order below - "-lskia" last - which is what the dui project
#     already does.
#  2. skcms, pathops, the CoreText font manager and (when enabled) Ganesh all
#     end up inside libskia.a, because existing consumers link "-lskia" alone.

if(SKIA_BUILD_METAL)
  enable_language(OBJCXX)
endif()

# ---------------------------------------------------------------------------
# skcms - its own objects, folded into libskia.a and also emitted standalone.
# ---------------------------------------------------------------------------
add_library(skcms_objects OBJECT ${SKIA_SKCMS_SOURCES})
target_include_directories(skcms_objects PRIVATE "${SKIA_ROOT}")
target_compile_options(skcms_objects PRIVATE -Wno-attributes)
if(NOT SKIA_ARCH_X86_64)
  target_compile_definitions(skcms_objects PRIVATE SKCMS_DISABLE_HSW SKCMS_DISABLE_SKX)
else()
  set_source_files_properties("${SKIA_ROOT}/modules/skcms/src/skcms_TransformHsw.cc"
      PROPERTIES COMPILE_OPTIONS "-mavx2;-mf16c")
  set_source_files_properties("${SKIA_ROOT}/modules/skcms/src/skcms_TransformSkx.cc"
      PROPERTIES COMPILE_OPTIONS "-mavx512f;-mavx512dq;-mavx512cd;-mavx512bw;-mavx512vl")
endif()

# ---------------------------------------------------------------------------
# libskia.a
# ---------------------------------------------------------------------------
skia_gni_sources(SKIA_SOURCES
    skia_core_sources
    skia_utils_private
    skia_effects_sources
    skia_colorfilters_sources
    skia_effects_imagefilter_sources
    skia_clipstack_utils_sources
    skia_pathops_sources
    skia_sksl_core_sources
    skia_sksl_core_module_sources
    skia_ports_sources
    skia_codec_shared
    skia_codec_decode_bmp
    skia_encode_srcs)
list(APPEND SKIA_SOURCES ${SKIA_EXTRA_SOURCES} ${SKIA_PLATFORM_PORT_SOURCES}
                         ${SKIA_ARCH_OPT_SOURCES})

if(SKIA_HAVE_LIBPNG)
  skia_gni_sources(SKIA_SOURCES skia_codec_png_base skia_codec_libpng_srcs
                                 skia_encode_png_base skia_encode_libpng_srcs)
  list(APPEND SKIA_SOURCES ${SKIA_ICO_CODEC_SOURCES})
else()
  # BUILD.gn:2077-2079 - the encoder entry points still have to exist.
  skia_gni_sources(SKIA_SOURCES skia_no_encode_png_srcs)
endif()
if(SKIA_HAVE_JPEG)
  skia_gni_sources(SKIA_SOURCES skia_encode_jpeg_srcs)
  list(APPEND SKIA_SOURCES ${SKIA_JPEG_DECODE_SOURCES})
else()
  skia_gni_sources(SKIA_SOURCES skia_no_encode_jpeg_srcs)   # BUILD.gn:2075-2076
endif()
if(SKIA_HAVE_WEBP)
  skia_gni_sources(SKIA_SOURCES skia_encode_webp_srcs)
  list(APPEND SKIA_SOURCES ${SKIA_WEBP_DECODE_SOURCES})
else()
  skia_gni_sources(SKIA_SOURCES skia_no_encode_webp_srcs)   # BUILD.gn:2080-2081
endif()
if(SKIA_HAVE_EXPAT)
  skia_gni_sources(SKIA_SOURCES skia_xml_sources skia_codec_xmp skia_svg_writer_sources)
endif()
if(SKIA_BUILD_PDF)
  skia_gni_sources(SKIA_SOURCES skia_pdf_sources)
else()
  list(APPEND SKIA_SOURCES "${SKIA_ROOT}/src/pdf/SkDocument_PDF_None.cpp")
endif()

if(SKIA_HAVE_FREETYPE)
  skia_gni_sources(SKIA_SOURCES skia_ports_freetype_sources)
  if(SKIA_BUILD_FONT_MGRS)
    skia_gni_sources(SKIA_SOURCES skia_ports_fontmgr_custom_sources
                                   skia_ports_fontmgr_directory_sources
                                   skia_ports_fontmgr_embedded_sources
                                   skia_ports_fontmgr_empty_sources
                                   skia_ports_typeface_proxy_sources)
  endif()
endif()
if(SKIA_PLATFORM_APPLE)
  skia_gni_sources(SKIA_SOURCES skia_ports_fontmgr_coretext_sources)
elseif(SKIA_HAVE_FONTCONFIG)
  skia_gni_sources(SKIA_SOURCES skia_ports_fontmgr_fontconfig_sources)
endif()

if(SKIA_BUILD_GANESH)
  skia_gni_sources(SKIA_SOURCES skia_shared_gpu_sources skia_sksl_pipeline_sources
                                 skia_sksl_codegen_sources skia_ganesh_private)
  if(SKIA_BUILD_GL)
    skia_gni_sources(SKIA_SOURCES skia_gpu_gl_private)
    list(APPEND SKIA_SOURCES ${SKIA_GL_NATIVE_SOURCES})
  endif()
  if(SKIA_BUILD_METAL)
    skia_gni_sources(SKIA_SOURCES skia_gpu_metal_private skia_shared_mtl_sources)
  endif()
endif()

list(REMOVE_DUPLICATES SKIA_SOURCES)

add_library(skia STATIC ${SKIA_SOURCES})
set_target_properties(skia PROPERTIES OUTPUT_NAME skia)
target_sources(skia PRIVATE $<TARGET_OBJECTS:skcms_objects>)
target_include_directories(skia PUBLIC "${SKIA_ROOT}")
target_compile_definitions(skia
    PUBLIC ${SKIA_PUBLIC_DEFINES}
    PRIVATE ${SKIA_PRIVATE_DEFINES})
skia_apply_compile_options(skia)
target_link_libraries(skia PUBLIC ${SKIA_SYSTEM_LIBS})
if(SKIA_BUILD_METAL)
  target_compile_options(skia PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
  target_compile_options(skcms_objects PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
endif()

if(SKIA_BUILD_SKCMS)
  add_library(skcms STATIC)
  set_target_properties(skcms PROPERTIES OUTPUT_NAME skcms)
  target_sources(skcms PRIVATE $<TARGET_OBJECTS:skcms_objects>)
  target_include_directories(skcms PUBLIC "${SKIA_ROOT}")
endif()

# ---------------------------------------------------------------------------
# Modules. skresources is an OBJECT library because its objects are needed
# inside both libsvg.a and libskottie.a (GN gives each complete library its own
# copy); skshaper/sksg/jsonreader are plain archives.
# ---------------------------------------------------------------------------
if(SKIA_BUILD_MODULES)

  function(skia_module_target target output_name)
    add_library(${target} STATIC ${ARGN})
    set_target_properties(${target} PROPERTIES OUTPUT_NAME ${output_name})
    target_include_directories(${target} PUBLIC "${SKIA_ROOT}")
    target_compile_definitions(${target} PRIVATE ${SKIA_PRIVATE_DEFINES})
    skia_apply_compile_options(${target})
  endfunction()

  # --- skunicode (needed by svg, skottie and skshaper) ---
  if(SKIA_HAVE_ICU)
    # modules/skunicode: "skunicode_core" plus "skunicode_icu", which in GN is a
    # separate component. We fold them into one archive.
    skia_gni_sources(SKUNICODE_SOURCES skia_unicode_sources
                                      skia_unicode_icu_sources
                                      skia_unicode_icu_bidi_sources
                                      skia_unicode_bidi_full_sources
                                      skia_unicode_builtin_icu_sources)
    add_library(skunicode_core STATIC ${SKUNICODE_SOURCES})
    set_target_properties(skunicode_core PROPERTIES OUTPUT_NAME skunicode_core)
    target_include_directories(skunicode_core PUBLIC "${SKIA_ROOT}")
    target_compile_definitions(skunicode_core PRIVATE
        ${SKIA_PRIVATE_DEFINES}
        SKUNICODE_IMPLEMENTATION=1
        U_USING_ICU_NAMESPACE=0
        U_SHOW_CPLUSPLUS_API=0)
    skia_apply_compile_options(skunicode_core)
    target_link_libraries(skunicode_core PUBLIC skia)
  endif()

  # --- skresources ---
  skia_gni_sources(SKRESOURCES_SOURCES skia_skresources_sources)
  add_library(skresources_objects OBJECT ${SKRESOURCES_SOURCES})
  target_include_directories(skresources_objects PUBLIC "${SKIA_ROOT}")
  target_compile_definitions(skresources_objects PRIVATE ${SKIA_PRIVATE_DEFINES})
  skia_apply_compile_options(skresources_objects)
  if(SKIA_BUILD_SKRESOURCES)
    add_library(skresources STATIC)
    set_target_properties(skresources PROPERTIES OUTPUT_NAME skresources)
    target_sources(skresources PRIVATE $<TARGET_OBJECTS:skresources_objects>)
    target_include_directories(skresources PUBLIC "${SKIA_ROOT}")
  endif()

  # --- jsonreader ---
  skia_gni_sources(JSONREADER_SOURCES skia_jsonreader_sources)
  skia_module_target(jsonreader jsonreader ${JSONREADER_SOURCES})
  target_link_libraries(jsonreader PUBLIC skia)

  # --- sksg ---
  skia_gni_sources(SKSG_SOURCES skia_sksg_sources)
  skia_module_target(sksg sksg ${SKSG_SOURCES})
  target_compile_definitions(sksg PUBLIC SK_ENABLE_SKSG=1)
  target_link_libraries(sksg PUBLIC skia)

  # --- skshaper ---
  skia_gni_sources(SKSHAPER_SOURCES skia_shaper_primitive_sources)
  if(SKIA_PLATFORM_APPLE)
    skia_gni_sources(SKSHAPER_SOURCES skia_shaper_coretext_sources)
  endif()
  if(SKIA_HAVE_ICU)
    skia_gni_sources(SKSHAPER_SOURCES skia_shaper_skunicode_sources)
  endif()
  if(SKIA_HAVE_HARFBUZZ AND SKIA_HAVE_ICU)
    skia_gni_sources(SKSHAPER_SOURCES skia_shaper_harfbuzz_sources)
  endif()
  skia_module_target(skshaper skshaper ${SKSHAPER_SOURCES})
  target_compile_definitions(skshaper
      PUBLIC SK_SHAPER_PRIMITIVE_AVAILABLE
      PRIVATE SKSHAPER_IMPLEMENTATION=1)
  if(SKIA_PLATFORM_APPLE)
    target_compile_definitions(skshaper PUBLIC SK_SHAPER_CORETEXT_AVAILABLE)
  endif()
  if(SKIA_HAVE_HARFBUZZ)
    target_compile_definitions(skshaper PUBLIC SK_SHAPER_HARFBUZZ_AVAILABLE)
  endif()
  if(SKIA_HAVE_ICU)
    target_compile_definitions(skshaper PUBLIC SK_SHAPER_UNICODE_AVAILABLE)
  endif()
  target_link_libraries(skshaper PUBLIC skia)
  if(TARGET skunicode_core)
    target_link_libraries(skshaper PUBLIC skunicode_core)
  endif()

  # --- svg (requires expat, exactly like GN's `if (skia_enable_svg && skia_use_expat)`) ---
  if(SKIA_HAVE_EXPAT)
    skia_gni_sources(SVG_SOURCES skia_svg_renderer_sources)
    skia_module_target(svg svg ${SVG_SOURCES} $<TARGET_OBJECTS:skresources_objects>)
    target_compile_definitions(svg PUBLIC SK_ENABLE_SVG=1)
    target_include_directories(svg PUBLIC "${SKIA_ROOT}/modules/svg/include")
    target_link_libraries(svg PUBLIC skia skshaper)
    if(TARGET skunicode_core)
      target_link_libraries(svg PUBLIC skunicode_core)
    endif()
  endif()

  # --- skottie ---
  skia_gni_sources(SKOTTIE_SOURCES skia_skottie_sources)
  skia_module_target(skottie skottie ${SKOTTIE_SOURCES} $<TARGET_OBJECTS:skresources_objects>)
  target_compile_definitions(skottie
      PUBLIC SK_ENABLE_SKOTTIE=1 SK_ENABLE_SKOTTIE_SKSLEFFECT=1)
  target_include_directories(skottie PUBLIC "${SKIA_ROOT}/modules/skottie/include")
  target_link_libraries(skottie PUBLIC skia sksg skshaper jsonreader)
  if(TARGET skunicode_core)
    target_link_libraries(skottie PUBLIC skunicode_core)
  endif()

endif()

# ---------------------------------------------------------------------------
# Smoke test: exercises one entry point of every archive, in dui's link order.
# ---------------------------------------------------------------------------
if(SKIA_BUILD_SMOKE_TEST)
  add_executable(skia_smoke_test "${SKIA_ROOT}/cmake/smoke_test/skia_smoke_test.cpp")
  skia_apply_compile_options(skia_smoke_test)
  if(TARGET svg)
    target_link_libraries(skia_smoke_test PRIVATE
        svg skshaper skottie sksg jsonreader skia)
  else()
    target_link_libraries(skia_smoke_test PRIVATE skia)
  endif()
endif()

# ---------------------------------------------------------------------------
# Export the information a consumer (e.g. the dui project) needs.
# ---------------------------------------------------------------------------
set(SKIA_EXPORT_INCLUDE_DIRS "${SKIA_ROOT}")
set(SKIA_EXPORT_DEFINES "${SKIA_PUBLIC_DEFINES}")
# Link order matters: SKIA_LINK_LIBS is a plain "-l" list for consumers, not a
# target graph, so every archive has to precede the ones it needs. The modules
# come first (dui's own order is svg skshaper skottie sksg jsonreader skia) and
# "-lskia" comes last. skunicode_core is named explicitly because, unlike skcms,
# its objects are not folded into libskia.a.
set(SKIA_EXPORT_LIBRARIES)
foreach(_mod svg skshaper skottie sksg jsonreader skresources skcms skunicode_core)
  if(TARGET ${_mod})
    list(APPEND SKIA_EXPORT_LIBRARIES ${_mod})
  endif()
endforeach()
list(APPEND SKIA_EXPORT_LIBRARIES skia)
set(SKIA_EXPORT_SYSTEM_LIBS "${SKIA_DEP_LIB_NAMES}")
set(SKIA_EXPORT_SYSTEM_LIB_DIRS "${SKIA_DEP_LIB_DIRS}")
if(SKIA_PLATFORM_APPLE)
  # "-Wl,-framework,Name" rather than "-framework Name": the export below is a
  # flat ";"-separated list in a generated set(), so an entry containing a space
  # would come back as two list items and be linked as -l<Name>.
  list(APPEND SKIA_EXPORT_SYSTEM_LIBS
       -Wl,-framework,ApplicationServices
       -Wl,-framework,AppKit
       -Wl,-framework,CoreFoundation
       -Wl,-framework,CoreGraphics
       -Wl,-framework,CoreText)
  if(SKIA_BUILD_METAL)
    list(APPEND SKIA_EXPORT_SYSTEM_LIBS -Wl,-framework,Metal -Wl,-framework,Foundation)
  endif()
endif()
set(SKIA_EXPORT_LIBRARY_DIR "${CMAKE_BINARY_DIR}")
configure_file("${SKIA_ROOT}/cmake/SkiaConfig.cmake.in"
               "${CMAKE_BINARY_DIR}/skia-vars.cmake" @ONLY)

if(SKIA_INSTALL)
  include(GNUInstallDirs)
  install(TARGETS ${SKIA_EXPORT_LIBRARIES}
          ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}")
  install(DIRECTORY "${SKIA_ROOT}/include/" DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}")
  install(FILES "${CMAKE_BINARY_DIR}/skia-vars.cmake"
          DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/skia")
endif()
