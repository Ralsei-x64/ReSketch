// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include "include/cef_render_handler.h"
#include <QSize>
#include <memory>
struct CefTextureFrame {
    unsigned texture = 0;
    QSize size;
    ~CefTextureFrame();
};
// Copies a CEF DMA-BUF to our own GPU texture before CEF returns it to its pool.
std::shared_ptr<CefTextureFrame> copyCefTexture(const CefAcceleratedPaintInfo &info);
bool cefSharedTexturesSupported();
