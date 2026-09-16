/*
 * Copyright 2026 The Skia Authors
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * End-to-end check of a CMake-built Skia: draws with the raster backend, renders
 * text through the platform font manager, encodes a PNG, and touches one entry
 * point of every module archive. Exits non-zero on the first failure, so it can
 * be used as a build step.
 */

#include "include/core/SkBitmap.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkImage.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkStream.h"
#include "include/core/SkSurface.h"
#include "include/encode/SkPngEncoder.h"

#if defined(SK_BUILD_FOR_MAC) || defined(SK_BUILD_FOR_IOS)
#include "include/ports/SkFontMgr_mac_ct.h"
#elif defined(SK_BUILD_FOR_UNIX)
#include "include/ports/SkFontMgr_fontconfig.h"
#endif

#include "modules/jsonreader/SkJSONReader.h"
#include "modules/sksg/include/SkSGDraw.h"
#include "modules/sksg/include/SkSGGroup.h"
#include "modules/sksg/include/SkSGPaint.h"
#include "modules/sksg/include/SkSGRect.h"
#include "modules/sksg/include/SkSGScene.h"
#include "modules/skshaper/include/SkShaper.h"
#include "modules/skshaper/include/SkShaper_factory.h"
#include "modules/skottie/include/Skottie.h"
#include "modules/svg/include/SkSVGDOM.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

int g_failures = 0;

void check(bool ok, const char* what) {
    std::printf("%-46s %s\n", what, ok ? "ok" : "FAILED");
    if (!ok) {
        ++g_failures;
    }
}

sk_sp<SkFontMgr> make_font_mgr() {
#if defined(SK_BUILD_FOR_MAC) || defined(SK_BUILD_FOR_IOS)
    return SkFontMgr_New_CoreText(nullptr);
#elif defined(SK_BUILD_FOR_UNIX)
    return SkFontMgr_New_FontConfig(nullptr, nullptr);
#else
    return nullptr;
#endif
}

const char kMinimalLottie[] = R"({
  "v": "5.5.7", "fr": 30, "ip": 0, "op": 30, "w": 100, "h": 100, "nm": "smoke",
  "ddd": 0, "assets": [], "layers": []
})";

const char kMinimalSvg[] = R"(<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
  <rect x="4" y="4" width="24" height="24" fill="#3366ff"/>
</svg>)";

}  // namespace

int main() {
    constexpr int kWidth = 256, kHeight = 256, kTextTop = 150;

    // 1. Raster surface + CPU drawing.
    auto surface = SkSurfaces::Raster(SkImageInfo::MakeN32Premul(kWidth, kHeight));
    check(surface != nullptr, "raster surface");
    if (!surface) {
        return 1;
    }
    SkCanvas* canvas = surface->getCanvas();
    canvas->clear(SK_ColorWHITE);

    SkPaint paint;
    paint.setColor(SK_ColorRED);
    paint.setAntiAlias(true);
    canvas->drawRect(SkRect::MakeLTRB(16, 16, 112, 112), paint);

    paint.setColor(SK_ColorBLUE);
    SkPathBuilder pathBuilder;
    pathBuilder.moveTo(128, 16);
    pathBuilder.lineTo(240, 112);
    pathBuilder.lineTo(128, 112);
    pathBuilder.close();
    canvas->drawPath(pathBuilder.detach(), paint);

    // 2. Text through the platform font manager.
    bool drew_text = false;
    if (auto fontMgr = make_font_mgr()) {
        if (auto typeface = fontMgr->matchFamilyStyle(nullptr, SkFontStyle())) {
            SkFont font(typeface, 40);
            SkPaint textPaint;
            textPaint.setColor(SK_ColorBLACK);
            canvas->drawString("Skia", 24, kTextTop + 40, font, textPaint);
            drew_text = true;
        }
    }
    check(drew_text, "font manager + text");

    // 3. The draws actually landed in the pixels.
    SkBitmap bitmap;
    if (!bitmap.tryAllocPixels(surface->imageInfo()) ||
        !surface->readPixels(bitmap.pixmap(), 0, 0)) {
        check(false, "read back pixels");
        return 1;
    }
    int non_white = 0, blue = 0, black_in_text_band = 0;
    for (int y = 0; y < kHeight; ++y) {
        for (int x = 0; x < kWidth; ++x) {
            const SkColor c = bitmap.getColor(x, y);
            if (c != SK_ColorWHITE) {
                ++non_white;
            }
            if (SkColorGetB(c) > 200 && SkColorGetR(c) < 100) {
                ++blue;
            }
            if (y > kTextTop && SkColorGetR(c) < 100) {
                ++black_in_text_band;
            }
        }
    }
    check(non_white > 1000, "drawn pixels");
    check(blue > 500, "path pixels");
    if (drew_text) {
        check(black_in_text_band > 30, "glyph pixels");
    }

    // 4. PNG encoding.
    SkDynamicMemoryWStream stream;
    const bool encoded = SkPngEncoder::Encode(&stream, bitmap.pixmap(), {});
    auto data = stream.detachAsData();
    const auto* bytes = static_cast<const unsigned char*>(data->data());
    const bool png_magic = data->size() > 8 && bytes[0] == 0x89 && bytes[1] == 'P' &&
                           bytes[2] == 'N' && bytes[3] == 'G';
    check(encoded && png_magic, "png encode");

    // 5. Every module archive, one entry point each.
    if (auto svgStream = SkMemoryStream::MakeDirect(kMinimalSvg, sizeof(kMinimalSvg) - 1)) {
        auto dom = SkSVGDOM::MakeFromStream(*svgStream);
        if (dom) {
            dom->render(canvas);
        }
        check(dom != nullptr, "svg render");
    }

    auto shaper = SkShapers::Primitive::Factory()->makeShaper(nullptr);
    check(shaper != nullptr, "skshaper");

    skjson::DOM json("{\"a\": 1}", 8);
    check(json.root().is<skjson::ObjectValue>(), "jsonreader");

    auto group = sksg::Group::Make();
    group->addChild(sksg::Draw::Make(sksg::Rect::Make(SkRect::MakeXYWH(0, 0, 48, 48)),
                                     sksg::Color::Make(SK_ColorGREEN)));
    auto scene = sksg::Scene::Make(group);
    check(scene != nullptr, "sksg");
    if (scene) {
        scene->render(canvas);
    }

    auto animation = skottie::Animation::Make(kMinimalLottie, sizeof(kMinimalLottie) - 1);
    check(animation != nullptr, "skottie");
    if (animation) {
        animation->render(canvas);
    }

    // The module draws above went to the same canvas - make sure they landed.
    if (bitmap.tryAllocPixels(surface->imageInfo()) &&
        surface->readPixels(bitmap.pixmap(), 0, 0)) {
        int non_white_after = 0, green = 0;
        for (int y = 0; y < kHeight; ++y) {
            for (int x = 0; x < kWidth; ++x) {
                const SkColor c = bitmap.getColor(x, y);
                if (c != SK_ColorWHITE) {
                    ++non_white_after;
                }
                if (SkColorGetG(c) > 150 && SkColorGetR(c) < 120 && SkColorGetB(c) < 120) {
                    ++green;
                }
            }
        }
        check(non_white_after > non_white, "module draws reached the canvas");
        check(green > 500, "sksg pixels");
    }

    std::printf("\n%s (%d bytes of PNG)\n",
                g_failures == 0 ? "skia_smoke_test: PASSED" : "skia_smoke_test: FAILED",
                static_cast<int>(data->size()));
    return g_failures == 0 ? 0 : 1;
}
