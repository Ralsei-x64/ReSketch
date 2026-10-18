// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <QElapsedTimer>
#include <QKeyEvent>
#include <QKeySequence>
#include <QMouseEvent>
#include <QObject>
#include <QPointer>
#include <QSettings>
#include <QWindow>
#include <QWheelEvent>
#include <QColor>
#include <QGuiApplication>
#include <QFont>
#include <QVariantMap>

class StreamerMode : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed)
    Q_PROPERTY(int xPosition READ xPosition WRITE setXPosition NOTIFY changed)
    Q_PROPERTY(int yPosition READ yPosition WRITE setYPosition NOTIFY changed)
    Q_PROPERTY(int durationMs READ durationMs WRITE setDurationMs NOTIFY changed)
    Q_PROPERTY(bool spawnUpwards READ spawnUpwards WRITE setSpawnUpwards NOTIFY changed)
    Q_PROPERTY(int spawnDirection READ spawnDirection WRITE setSpawnDirection NOTIFY changed)
    Q_PROPERTY(QVariantMap style READ style WRITE setStyle NOTIFY changed)
    Q_PROPERTY(int maximumEntries READ maximumEntries WRITE setMaximumEntries NOTIFY changed)

public:
    explicit StreamerMode(QObject *parent = nullptr) : QObject(parent) { clock.start(); }
    bool enabled() const { return settings.value("streamer/enabled", false).toBool(); }
    int xPosition() const { return qBound(0, settings.value("streamer/x", 2).toInt(), 100); }
    int yPosition() const { return qBound(0, settings.value("streamer/y", 95).toInt(), 100); }
    int durationMs() const { return qBound(500, settings.value("streamer/durationMs", 2000).toInt(), 10000); }
    int spawnDirection() const { return qBound(0, settings.value("streamer/spawnDirection",
        settings.value("streamer/spawnUpwards", false).toBool() ? 1 : 0).toInt(), 3); }
    bool spawnUpwards() const { return spawnDirection() == 1; }
    QVariantMap style() const { return normalizedStyle(settings.value("streamer/style").toMap()); }
    int maximumEntries() const { return qBound(1, settings.value("streamer/maximumEntries", 8).toInt(), 32); }
    void setEnabled(bool value)
    {
        if (enabled() == value) return;
        settings.setValue("streamer/enabled", value);
        pendingWindow.clear();
        emit changed();
        emit cleared();
    }
    void setXPosition(int value) { settings.setValue("streamer/x", qBound(0, value, 100)); emit changed(); }
    void setYPosition(int value) { settings.setValue("streamer/y", qBound(0, value, 100)); emit changed(); }
    void setDurationMs(int value) { settings.setValue("streamer/durationMs", qBound(500, value, 10000)); emit changed(); }
    void setSpawnDirection(int value) { settings.setValue("streamer/spawnDirection", qBound(0, value, 3)); emit changed(); }
    void setSpawnUpwards(bool value) { setSpawnDirection(value ? 1 : 0); }
    void setStyle(const QVariantMap &value) { settings.setValue("streamer/style", normalizedStyle(value)); emit changed(); }
    void setMaximumEntries(int value) { settings.setValue("streamer/maximumEntries", qBound(1, value, 32)); emit changed(); }
    void reload()
    {
        settings.sync();
        pendingWindow.clear();
        emit changed();
        emit cleared();
    }

    // Called only for registered ReSketch main windows. Never consumes input.
    void observe(QWindow *window, QEvent *event)
    {
        if (!enabled()) return;
        if (event->type() == QEvent::WindowDeactivate) {
            if (pendingWindow == window) pendingWindow.clear();
            return;
        }
        const bool replace = pendingWindow == window && clock.elapsed() - pendingSince < pendingDuration;
        if (event->type() == QEvent::Wheel) {
            const auto *wheel = static_cast<QWheelEvent *>(event);
            const int delta = wheel->angleDelta().y() ? wheel->angleDelta().y() : wheel->pixelDelta().y();
            if (!delta) return;
            const int steps = wheel->angleDelta().y() ? qMax(1, qAbs(delta) / 120) : 1;
            pendingWindow.clear();
            emit scrolled(window, delta > 0 ? steps : -steps,
                          modifierNames(wheel->modifiers()).join(QStringLiteral(" + ")), replace);
            return;
        }
        QString label;
        bool modifierOnly = false;
        if (event->type() == QEvent::ShortcutOverride) {
            // Observe before Qt dispatches shortcuts, including shortcuts whose
            // KeyPress never reaches the focused Chromium/Quick item.
            const auto *key = static_cast<QKeyEvent *>(event);
            if (key->isAutoRepeat() || key->key() == Qt::Key_unknown || !key->key()) return;
            auto modifiers = key->modifiers();
            switch (key->key()) {
            case Qt::Key_Control: modifiers |= Qt::ControlModifier; modifierOnly = true; break;
            case Qt::Key_Shift: modifiers |= Qt::ShiftModifier; modifierOnly = true; break;
            case Qt::Key_Alt: modifiers |= Qt::AltModifier; modifierOnly = true; break;
            case Qt::Key_Meta: modifiers |= Qt::MetaModifier; modifierOnly = true; break;
            case Qt::Key_AltGr: label = tr("AltGr"); modifierOnly = true; break;
            default: break;
            }
            QStringList parts = modifierNames(modifiers);
            if (!modifierOnly) label = QKeySequence(key->key()).toString(QKeySequence::NativeText);
            if (!label.isEmpty()) parts << label;
            label = parts.join(QStringLiteral(" + "));
        } else if (event->type() == QEvent::KeyRelease) {
            const auto *key = static_cast<QKeyEvent *>(event);
            if (!key->isAutoRepeat() && (key->key() == Qt::Key_Control || key->key() == Qt::Key_Shift
                    || key->key() == Qt::Key_Alt || key->key() == Qt::Key_Meta || key->key() == Qt::Key_AltGr))
                pendingWindow.clear();
            return;
        } else if (event->type() == QEvent::MouseButtonPress || event->type() == QEvent::MouseButtonDblClick) {
            const auto *mouse = static_cast<QMouseEvent *>(event);
            switch (mouse->button()) {
            case Qt::LeftButton: label = tr("Mouse Left"); break;
            case Qt::RightButton: label = tr("Mouse Right"); break;
            case Qt::MiddleButton: label = tr("Mouse Middle"); break;
            case Qt::BackButton: label = tr("Mouse Back"); break;
            case Qt::ForwardButton: label = tr("Mouse Forward"); break;
            default: label = tr("Mouse %1").arg(quint32(mouse->button())); break;
            }
            QStringList parts = modifierNames(mouse->modifiers());
            parts << label;
            label = parts.join(QStringLiteral(" + "));
        }
        if (label.isEmpty()) return;
        emit pressed(window, label, replace);
        if (modifierOnly) {
            if (!replace) {
                pendingSince = clock.elapsed();
                pendingDuration = durationMs();
            }
            pendingWindow = window;
        } else pendingWindow.clear();
    }

signals:
    void changed();
    void cleared();
    void pressed(QWindow *window, const QString &label, bool replace);
    void scrolled(QWindow *window, int steps, const QString &modifiers, bool replaceModifier);

private:
    static QVariantMap normalizedStyle(const QVariantMap &input)
    {
        QVariantMap result{{"marginX", 12}, {"marginY", 12},
            {"paddingLeft", 12}, {"paddingRight", 12}, {"paddingTop", 8}, {"paddingBottom", 8}, {"minWidth", 0}, {"minHeight", 34}, {"alignment", 0},
            {"background", "#20232a"}, {"textColor", "#ffffff"},
            {"fontFamily", QGuiApplication::font().family()}, {"fontSize", 14},
            {"radius", 8}, {"transparency", 19}, {"blur", 0}, {"shadow", false}, {"shadowStrength", 35},
            {"sticky", false}, {"horizontalAnchor", 0}, {"verticalAnchor", 1}, {"offsetX", 0}, {"offsetY", 0}};
        const auto number = [&](const QString &key, int minimum, int maximum) {
            if (!input.contains(key)) return;
            bool valid = false;
            const int value = input.value(key).toInt(&valid);
            if (valid) result[key] = qBound(minimum, value, maximum);
        };
        // Preserve the old horizontal/vertical padding when loading older settings.
        for (const auto *axis : {"paddingX", "paddingY"}) number(axis, 0, 100);
        for (const auto *side : {"paddingLeft", "paddingRight"})
            if (result.contains("paddingX")) result[side] = result.value("paddingX");
        for (const auto *side : {"paddingTop", "paddingBottom"})
            if (result.contains("paddingY")) result[side] = result.value("paddingY");
        result.remove("paddingX"); result.remove("paddingY");
        for (const auto *key : {"marginX", "marginY", "paddingTop", "paddingRight", "paddingBottom", "paddingLeft", "radius"})
            number(key, 0, 100);
        for (const auto *key : {"transparency", "shadowStrength"}) number(key, 0, 100);
        for (const auto *key : {"offsetX", "offsetY"}) number(key, -10000, 10000);
        number("fontSize", 8, 96);
        number("minWidth", 0, 400);
        number("minHeight", 0, 200);
        number("alignment", 0, 4);
        number("horizontalAnchor", 0, 2);
        number("verticalAnchor", 0, 2);
        number("blur", 0, 32);
        for (const auto *key : {"shadow", "sticky"})
            if (input.contains(key)) result[key] = input.value(key).toBool();
        for (const auto *key : {"background", "textColor"}) {
            const QColor color(input.value(key).toString());
            if (color.isValid()) result[key] = color.name();
        }
        const auto family = input.value("fontFamily").toString().trimmed().left(200);
        if (!family.isEmpty()) result["fontFamily"] = family;
        return result;
    }

    static QStringList modifierNames(Qt::KeyboardModifiers modifiers)
    {
        QStringList parts;
        if (modifiers & Qt::ControlModifier) parts << tr("Ctrl");
        if (modifiers & Qt::AltModifier) parts << tr("Alt");
        if (modifiers & Qt::ShiftModifier) parts << tr("Shift");
        if (modifiers & Qt::MetaModifier) parts << tr("Meta");
        return parts;
    }

    QSettings settings{QStringLiteral("aether64"), QStringLiteral("ReSketch")};
    QElapsedTimer clock;
    QPointer<QWindow> pendingWindow;
    qint64 pendingSince = 0;
    int pendingDuration = 2000;
};
