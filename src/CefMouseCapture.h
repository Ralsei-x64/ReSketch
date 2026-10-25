// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QObject>
#include <QPointF>
#include <functional>
#include <memory>
class QWindow;
class QMouseEvent;

// Relative motion on Wayland; recentering on X11. No Chromium pointer-lock emulation.
class CefMouseCapture final : public QObject {
public:
    explicit CefMouseCapture(QObject *parent);
    ~CefMouseCapture() override;
    bool start(QWindow *window, std::function<void(QPointF)> motion, std::function<void()> lost);
    void stop();
    bool move(QMouseEvent *event);
private:
    bool eventFilter(QObject *object, QEvent *event) override;
    struct State;
    std::unique_ptr<State> s;
};
