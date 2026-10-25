// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefMouseCapture.h"
#include <QCursor>
#include <cstring>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QPointer>
#include <QTimer>
#include <QWindow>
#include <qpa/qplatformnativeinterface.h>
#include <QtGui/qguiapplication_platform.h>
#include <wayland-client.h>
#include "pointer-constraints-client.h"
#include "relative-pointer-client.h"

struct CefMouseCapture::State {
    QPointer<QWindow> window;
    QPoint restore, anchor;
    bool active = false, locked = false;
    quint64 generation = 0;
    std::function<void(QPointF)> motion;
    std::function<void()> lost;
    wl_display *display = nullptr;
    wl_registry *registry = nullptr;
    zwp_pointer_constraints_v1 *constraints = nullptr;
    zwp_relative_pointer_manager_v1 *relativeManager = nullptr;
    zwp_relative_pointer_v1 *relative = nullptr;
    zwp_locked_pointer_v1 *lock = nullptr;
    quint32 constraintsName = 0, relativeName = 0;
};
CefMouseCapture::CefMouseCapture(QObject *parent) : QObject(parent), s(std::make_unique<State>()) {
#if QT_CONFIG(wayland)
    if (auto *native = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()) {
        s->display = native->display();
        s->registry = wl_display_get_registry(s->display);
        static const wl_registry_listener listener = {
            [](void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t) {
                auto *self = static_cast<CefMouseCapture *>(data);
                if (!strcmp(interface, zwp_pointer_constraints_v1_interface.name)) {
                    self->s->constraints = static_cast<zwp_pointer_constraints_v1 *>(wl_registry_bind(registry, name, &zwp_pointer_constraints_v1_interface, 1));
                    self->s->constraintsName = name;
                } else if (!strcmp(interface, zwp_relative_pointer_manager_v1_interface.name)) {
                    self->s->relativeManager = static_cast<zwp_relative_pointer_manager_v1 *>(wl_registry_bind(registry, name, &zwp_relative_pointer_manager_v1_interface, 1));
                    self->s->relativeName = name;
                }
            },
            [](void *data, wl_registry *, uint32_t name) {
                auto *self = static_cast<CefMouseCapture *>(data);
                if (name != self->s->constraintsName && name != self->s->relativeName) return;
                auto lost = self->s->lost; self->stop();
                if (name == self->s->constraintsName && self->s->constraints) {
                    zwp_pointer_constraints_v1_destroy(self->s->constraints); self->s->constraints = nullptr;
                }
                if (name == self->s->relativeName && self->s->relativeManager) {
                    zwp_relative_pointer_manager_v1_destroy(self->s->relativeManager); self->s->relativeManager = nullptr;
                }
                if (lost) lost();
            }
        };
        wl_registry_add_listener(s->registry, &listener, this);
        wl_display_flush(s->display);
    }
#endif
}
CefMouseCapture::~CefMouseCapture() {
    stop();
    if (s->constraints) zwp_pointer_constraints_v1_destroy(s->constraints);
    if (s->relativeManager) zwp_relative_pointer_manager_v1_destroy(s->relativeManager);
    if (s->registry) wl_registry_destroy(s->registry);
}
bool CefMouseCapture::start(QWindow *window, std::function<void(QPointF)> motion, std::function<void()> lost) {
    if (s->active || !window || !window->isActive() || !window->isVisible()) return false;
    s->window = window; s->restore = QCursor::pos(); s->motion = std::move(motion); s->lost = std::move(lost);
    if (s->display) {
#if QT_CONFIG(wayland)
        auto *native = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        auto *surface = static_cast<wl_surface *>(QGuiApplication::platformNativeInterface()->nativeResourceForWindow("surface", window));
        auto *pointer = native ? native->pointer() : nullptr;
        if (!s->constraints || !s->relativeManager || !surface || !pointer) { stop(); return false; }
        s->relative = zwp_relative_pointer_manager_v1_get_relative_pointer(s->relativeManager, pointer);
        static const zwp_relative_pointer_v1_listener relativeListener = {
            [](void *data, zwp_relative_pointer_v1 *, uint32_t, uint32_t, wl_fixed_t dx, wl_fixed_t dy, wl_fixed_t, wl_fixed_t) {
                auto *self = static_cast<CefMouseCapture *>(data);
                if (self->s->active && self->s->locked && self->s->motion)
                    self->s->motion({wl_fixed_to_double(dx), wl_fixed_to_double(dy)});
            }
        };
        zwp_relative_pointer_v1_add_listener(s->relative, &relativeListener, this);
        s->lock = zwp_pointer_constraints_v1_lock_pointer(s->constraints, surface, pointer, nullptr, ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_ONESHOT);
        static const zwp_locked_pointer_v1_listener lockListener = {
            [](void *data, zwp_locked_pointer_v1 *) { static_cast<CefMouseCapture *>(data)->s->locked = true; },
            [](void *data, zwp_locked_pointer_v1 *) {
                auto *self = static_cast<CefMouseCapture *>(data); auto lost = self->s->lost;
                self->stop(); if (lost) lost();
            }
        };
        zwp_locked_pointer_v1_add_listener(s->lock, &lockListener, this);
        s->active = true;
        window->installEventFilter(this);
        // A compositor may decline the constraint. Never leave an inert capture behind.
        QTimer::singleShot(500, this, [this, generation = ++s->generation] {
            if (!s->active || s->generation != generation || s->locked) return;
            auto lost = s->lost; stop(); if (lost) lost();
        });
        wl_display_flush(s->display);
        return true;
#endif
    }
    if (QGuiApplication::platformName() != "xcb") { stop(); return false; }
    s->active = true;
    window->installEventFilter(this);
    s->anchor = window->mapToGlobal(QPoint(window->width()/2, window->height()/2));
    QCursor::setPos(s->anchor);
    return true;
}
void CefMouseCapture::stop() {
    if (s->window) s->window->removeEventFilter(this);
    const bool restore = s->active && !s->display;
    s->active = false; s->locked = false; ++s->generation;
    if (s->lock) { zwp_locked_pointer_v1_destroy(s->lock); s->lock = nullptr; }
    if (s->relative) { zwp_relative_pointer_v1_destroy(s->relative); s->relative = nullptr; }
    if (restore && s->window && s->window->isActive()) QCursor::setPos(s->restore);
    if (s->display) wl_display_flush(s->display);
    s->motion = {}; s->lost = {}; s->window = nullptr;
}
bool CefMouseCapture::move(QMouseEvent *event) {
    if (!s->active) return false;
    if (!s->display) {
        const auto delta = event->globalPosition() - QPointF(s->anchor);
        if (!delta.isNull()) {
            if (s->motion) s->motion(delta);
            QCursor::setPos(s->anchor);
        }
    }
    return true;
}
bool CefMouseCapture::eventFilter(QObject *object, QEvent *event) {
    if (object == s->window && (event->type() == QEvent::WindowDeactivate || event->type() == QEvent::Hide
        || event->type() == QEvent::Close || event->type() == QEvent::PlatformSurface)) {
        auto lost = s->lost; stop(); if (lost) lost();
    }
    return false;
}
