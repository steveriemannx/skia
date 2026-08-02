/*
 * Copyright 2006 The Android Open Source Project
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */
#include "include/private/base/SkDebug.h"

#include <cstdarg>

#include "include/private/base/SkAssert.h" // IWYU pragma: keep
#include "include/private/base/SkAttributes.h" // IWYU pragma: keep
#include "include/private/base/SkLog.h"

#if defined(__FreeBSD__)
    #include <cstdarg>
    #include <cstdio>
    // Unified implementation for SkDebugf (variadic) and VSkDebugf (va_list)
    static void VSkDebugf(const char* format, va_list args) {
        vfprintf(stderr, format, args);
        fflush(stderr);
    }
    // The main debug output function
    void SkDebugf(const char format[], ...) {
        va_list args;
        va_start(args, format);
        VSkDebugf(format, args);  // Reuse VSkDebugf
        va_end(args);
    }
#endif

#if defined(SK_BUILD_FOR_GOOGLE3)
void SkDebugfForDumpStackTrace(const char* data, void* unused) {
    SkDebugf("%s", data);
}
#endif

#if !defined(SkDebugf) && !defined(__FreeBSD__)
void SkDebugf(const char format[], ...) {
    va_list args;
    va_start(args, format);
    SkLogVAList(SkLogPriority::kDebug, format, args);
    va_end(args);
}
#endif
