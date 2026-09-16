# Building Skia with CMake and bmake

This directory adds a hand-written CMake build for the Skia library. It is
**additive**: nothing here is read by the GN (`BUILD.gn`) or Bazel
(`BUILD.bazel`) builds, and no existing file needed to change.

The build uses bmake (NetBSD make) as its make program, and is always *driven by
cmake*: `cmake --build` invokes bmake and passes the job count down itself.

```sh
cmake/build_skia_bmake.sh                 # Release, host architecture
cmake/build_skia_bmake.sh Debug
BMAKE=/usr/bin/bmake JOBS=4 cmake/build_skia_bmake.sh Release -DSKIA_BUILD_METAL=ON
JOBS=1 cmake/build_skia_bmake.sh          # serial build, if -j ever stalls
```

Or by hand:

```sh
cmake -S . -B out/llvm.arm64.release -G "Unix Makefiles" \
      -DCMAKE_MAKE_PROGRAM="$(command -v bmake)" \
      -DCMAKE_BUILD_TYPE=Release
cmake --build out/llvm.arm64.release --parallel 8
```

Do not call bmake directly (`bmake -C out/llvm.arm64.release -j8`): a bare `-j`
is an error for bmake, and driving the recursive makefiles by hand has been seen
to stall on a full build. `cmake --build` is what keeps them in order.

## Artifacts

All archives land in the build directory (default `out/llvm.<arch>.<buildtype>/`):

| Archive | Contents |
| --- | --- |
| `libskia.a` | core + effects + SkSL + utils + ports + pathops + codecs + font managers + skcms + (Ganesh/GL, when enabled) |
| `libsvg.a`, `libskshaper.a`, `libskottie.a`, `libsksg.a`, `libjsonreader.a` | the modules |
| `libskresources.a`, `libskcms.a`, `libskunicode_core.a` | standalone copies of what is also folded into the archives above, for consumers that expect them |
| `skia-vars.cmake` | include this file to get the include dirs, defines and link line |
| `skia_smoke_test` | end-to-end check: draws, renders text, encodes a PNG, calls into every module |

Everything links statically; keep `skia` last on the link line.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `SKIA_BUILD_GANESH` | `ON` | Ganesh GPU backend (`SK_GANESH`) |
| `SKIA_BUILD_GL` | `ON` | Ganesh's OpenGL backend (`SK_GL`). On macOS this is a `dlopen` of the system OpenGL, so no framework is linked |
| `SKIA_BUILD_METAL` | `OFF` | Ganesh's Metal backend (`SK_METAL`); needs Objective-C++ |
| `SKIA_BUILD_GRAPHITE` | `OFF` | Graphite backend |
| `SKIA_BUILD_PDF` | `OFF` | `SK_SUPPORT_PDF` |
| `SKIA_BUILD_MODULES` | `ON` | svg / skottie / sksg / skshaper / jsonreader |
| `SKIA_BUILD_SMOKE_TEST` | `ON` | the `skia_smoke_test` executable |
| `SKIA_USE_LIBPNG`, `SKIA_USE_LIBJPEG_TURBO`, `SKIA_USE_LIBWEBP`, `SKIA_USE_ZLIB`, `SKIA_USE_EXPAT`, `SKIA_USE_FREETYPE`, `SKIA_USE_HARFBUZZ`, `SKIA_USE_ICU`, `SKIA_USE_FONTCONFIG` | `ON` | use the system library (see below) |
| `SKIA_USE_PERFETTO`, `SKIA_ENABLE_TRIVIAL_ABI`, `SKIA_BUILD_FONT_MGRS`, `SKIA_INSTALL` | `OFF` / `ON` | see `SkiaOptions.cmake` |
| `SKIA_PRESET` | `""` | `dui-parity` reproduces the argument set the dui project builds Skia with (no codecs, no PDF, no freetype/ICU) |

## Third party dependencies

Dependencies come from the system; `third_party/externals/` is *not* synced and
is not needed. On macOS/Homebrew:

```
freetype  harfbuzz  jpeg-turbo  libpng  webp  zlib*  expat*  icu4c
```

`zlib` and `expat` ship with the macOS SDK (`*`), everything else is found with
pkg-config/`find_package`. ICU is keg-only in Homebrew and is picked up from
`/opt/homebrew/opt/icu4c` automatically.

Dependencies that have no system package in this tree — wuffs, dng_sdk, piex,
brotli — are switched off, which means **no GIF decoding and no RAW/DNG
decoding** in this build. Run `tools/git-sync-deps` and extend
`SkiaSourceLists.cmake`/`SkiaTargets.cmake` if you need them.

## Where the source lists come from

`gn/*.gni` and `modules/*/*.gni` are generated from the Bazel build
(`make -C bazel generate_gni`) and are the canonical, always-current description
of which file belongs to which part of Skia. `gen_sources_from_gni.py` converts
them to a CMake file at configure time (`<build>/generated/skia_sources.cmake`),
so upstream rolls and regenerated `.gni` files need no changes here.

The script only accepts the narrow grammar those files actually use (literal
string arrays, `$_src`-style path prefixes). Anything else — a conditional, a
concatenation, an unknown path variable — aborts the configure with a `file:line`
diagnostic instead of quietly compiling the wrong set. What cannot come from a
`.gni` (the per-platform sources `BUILD.gn` adds by hand) lives in
`SkiaSourceLists.cmake` with the `BUILD.gn` line numbers.

## Consuming this build (e.g. from the dui project)

`skia-vars.cmake` is written into the build directory:

```cmake
include(".../third_party/skia/out/llvm.arm64.release/skia-vars.cmake")
include_directories(${SKIA_INCLUDE_DIRS})
add_compile_definitions(${SKIA_DEFINES})
link_directories("${SKIA_LIBRARY_DIR}" ${SKIA_SYSTEM_LIB_DIRS})
target_link_libraries(app ${SKIA_LINK_LIBS})
```

All four calls come before the targets that use them: `link_directories()` only
applies to targets declared after it, and `add_compile_definitions()` (not
`add_definitions()`) is the one that takes the bare macro names in
`SKIA_DEFINES`. The exported link line is in dependency order with `skia` last -
`cmake/smoke_test/skia_smoke_test.cpp` compiles and links against it as-is.

Because the build directory follows the `out/<compiler>.<arch>.<buildtype>`
naming the dui project already uses for prebuilt Skia, dropping this build into
`dui/third_party/skia/out/llvm.arm64.release/` makes dui pick it up without
touching its `link_directories()` setup — but the link line does need the system
libraries from `SKIA_LINK_LIBS` (`-lpng -ljpeg -lwebp -lwebpdemux -lwebpmux -lz
-lexpat -lfreetype -lharfbuzz -licuuc -licui18n`) since this build does not
absorb them into `libskia.a` the way the vendored third_party copies are.
Use `-DSKIA_PRESET=dui-parity` to build a library that needs none of them.

The defines matter: any translation unit that includes Skia headers must be
compiled with `SKIA_DEFINES` (`SK_GANESH`, `SK_GL`, the `SK_CODEC_*` set, and on
Linux `SK_R32_SHIFT=16`), otherwise it will disagree with the archive.

## Platforms

macOS is the primary target (arm64 and x86_64). Linux and FreeBSD are supported
for the CPU/codec/module configuration: `SK_BUILD_FOR_UNIX` is detected by
`include/private/SkFeatures.h`, the font manager switches to fontconfig, and the
GL backend needs `SKIA_USE_X11` (GLX) or falls back to
`GrGLMakeNativeInterface_none.cpp`. FreeBSD needs
`-DCMAKE_PREFIX_PATH=/usr/local` for the ports libraries.

## Notes and troubleshooting

* Out-of-source builds only; the build fails immediately otherwise.
* Build through `cmake --build <build dir> --parallel <n>` (that is what
  `cmake/build_skia_bmake.sh` does). cmake hands the job count to bmake and
  serializes the top-level recursive makes; invoking bmake by hand is the thing
  that has been seen to stall. `JOBS=1` (or `--parallel 1`) gives a strictly
  serial build.
* CMake marks the top-level makefiles `.NOTPARALLEL`, but the compiles happen one
  level down where parallelism is unrestricted — `--parallel 8` really does run 8
  compiles at once (8 `clang` processes were observed on an 8-core host).
* `ranlib: warning: 'libskia.a(SkFoo.cpp.o)' has no symbols` is expected: Skia's
  platform-specific sources are `#if`-guarded and compile to empty objects.
* `ld: warning: building for macOS-11.0, but linking with dylib ... built for
  newer version 26.0` comes from the Homebrew dylibs; override
  `-DCMAKE_OSX_DEPLOYMENT_TARGET=` if it bothers you.
* Editing a `.gni`, a `BUILD.gn`-derived source list or any `CMakeLists.txt`
  makes the next `cmake --build` reconfigure automatically.
