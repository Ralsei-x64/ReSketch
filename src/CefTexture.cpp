// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefTexture.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <QGuiApplication>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QPointer>

#include <array>

namespace {
class UploadContext : public QObject {
  public:
    UploadContext() : QObject(qGuiApp) {
        auto *share = QOpenGLContext::globalShareContext();
        if (!share)
            return;
        context.setFormat(share->format());
        context.setShareContext(share);
        if (!context.create())
            return;
        surface.setFormat(context.format());
        surface.create();
    }
    bool makeCurrent() { return surface.isValid() && context.isValid() && context.makeCurrent(&surface); }
    QOpenGLContext context;
    QOffscreenSurface surface;
};
QPointer<UploadContext> upload;
UploadContext *uploader() {
    if (!upload)
        upload = new UploadContext;
    return upload;
}
uint32_t fourcc(char a, char b, char c, char d) {
    return uint32_t(a) | (uint32_t(b) << 8) | (uint32_t(c) << 16) | (uint32_t(d) << 24);
}
} // namespace
bool cefSharedTexturesSupported() {
    return !qEnvironmentVariableIsSet("RESKETCH_CEF_BITMAP") &&
           !qEnvironmentVariable("RESKETCH_CEF_FLAGS").contains("disable-gpu") &&
           QGuiApplication::platformName() != "offscreen" && QGuiApplication::platformName() != "minimal";
}
CefTextureFrame::~CefTextureFrame() {
    if (!texture)
        return;
    if (auto *context = QOpenGLContext::currentContext())
        context->extraFunctions()->glDeleteTextures(1, &texture);
    else if (qGuiApp) {
        const unsigned id = texture;
        QMetaObject::invokeMethod(
            qGuiApp,
            [id] {
                auto *context = uploader();
                if (context->makeCurrent()) {
                    context->context.extraFunctions()->glDeleteTextures(1, &id);
                    context->context.doneCurrent();
                }
            },
            Qt::QueuedConnection);
    }
}
std::shared_ptr<CefTextureFrame> copyCefTexture(const CefAcceleratedPaintInfo &info) {
    if (info.plane_count <= 0 || info.plane_count > 4)
        return {};
    auto *context = uploader();
    if (!context->makeCurrent())
        return {};
    auto *gl = context->context.extraFunctions();
    const EGLDisplay display = eglGetCurrentDisplay();
    auto create = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(eglGetProcAddress("eglCreateImageKHR"));
    auto destroy = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(eglGetProcAddress("eglDestroyImageKHR"));
    auto bindImage =
        reinterpret_cast<void (*)(GLenum, void *)>(eglGetProcAddress("glEGLImageTargetTexture2DOES"));
    if (display == EGL_NO_DISPLAY || !create || !destroy || !bindImage) {
        context->context.doneCurrent();
        return {};
    }
    const auto &coded = info.extra.coded_size;
    const auto &visible = info.extra.visible_rect;
    const int width = visible.width > 0 ? visible.width : coded.width;
    const int height = visible.height > 0 ? visible.height : coded.height;
    const uint32_t format =
        info.format == CEF_COLOR_TYPE_RGBA_8888 ? fourcc('A', 'B', '2', '4') : fourcc('A', 'R', '2', '4');
    std::vector<EGLint> attrs{EGL_WIDTH,     coded.width, EGL_HEIGHT, coded.height, EGL_LINUX_DRM_FOURCC_EXT,
                              EGLint(format)};
    const std::array<EGLint, 4> fd{EGL_DMA_BUF_PLANE0_FD_EXT, EGL_DMA_BUF_PLANE1_FD_EXT,
                                   EGL_DMA_BUF_PLANE2_FD_EXT, EGL_DMA_BUF_PLANE3_FD_EXT};
    const std::array<EGLint, 4> offset{EGL_DMA_BUF_PLANE0_OFFSET_EXT, EGL_DMA_BUF_PLANE1_OFFSET_EXT,
                                       EGL_DMA_BUF_PLANE2_OFFSET_EXT, EGL_DMA_BUF_PLANE3_OFFSET_EXT};
    const std::array<EGLint, 4> pitch{EGL_DMA_BUF_PLANE0_PITCH_EXT, EGL_DMA_BUF_PLANE1_PITCH_EXT,
                                      EGL_DMA_BUF_PLANE2_PITCH_EXT, EGL_DMA_BUF_PLANE3_PITCH_EXT};
    const std::array<EGLint, 4> lo{EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
                                   EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT};
    const std::array<EGLint, 4> hi{EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT,
                                   EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT};
    const char *extensions = eglQueryString(display, EGL_EXTENSIONS);
    const bool modifiers =
        extensions && QByteArray(extensions).contains("EGL_EXT_image_dma_buf_import_modifiers");
    for (int i = 0; i < info.plane_count; ++i) {
        attrs.insert(attrs.end(), {fd[i], info.planes[i].fd, offset[i], EGLint(info.planes[i].offset),
                                   pitch[i], EGLint(info.planes[i].stride)});
        if (modifiers && info.modifier != uint64_t(-1))
            attrs.insert(attrs.end(),
                         {lo[i], EGLint(info.modifier & 0xffffffff), hi[i], EGLint(info.modifier >> 32)});
    }
    attrs.push_back(EGL_NONE);
    const EGLImageKHR image = create(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attrs.data());
    if (image == EGL_NO_IMAGE_KHR) {
        context->context.doneCurrent();
        return {};
    }
    GLuint imported = 0, texture = 0, read = 0, draw = 0;
    gl->glGenTextures(1, &imported);
    gl->glBindTexture(GL_TEXTURE_2D, imported);
    bindImage(GL_TEXTURE_2D, image);
    gl->glGenTextures(1, &texture);
    gl->glBindTexture(GL_TEXTURE_2D, texture);
    gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    gl->glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    gl->glGenFramebuffers(1, &read);
    gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, read);
    gl->glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, imported, 0);
    gl->glGenFramebuffers(1, &draw);
    gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw);
    gl->glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    const bool complete = gl->glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE &&
                          gl->glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    if (complete)
        gl->glBlitFramebuffer(visible.x, visible.y, visible.x + width, visible.y + height, 0, 0, width,
                              height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    // CEF explicitly releases the buffer when OnAcceleratedPaint returns. A dup
    // of its descriptor would keep memory alive but would not prevent reuse.
    gl->glFinish();
    gl->glBindFramebuffer(GL_FRAMEBUFFER, 0);
    gl->glDeleteFramebuffers(1, &read);
    gl->glDeleteFramebuffers(1, &draw);
    gl->glDeleteTextures(1, &imported);
    destroy(display, image);
    if (!complete)
        gl->glDeleteTextures(1, &texture);
    context->context.doneCurrent();
    if (!complete)
        return {};
    auto frame = std::make_shared<CefTextureFrame>();
    frame->texture = texture;
    frame->size = QSize(width, height);
    return frame;
}
