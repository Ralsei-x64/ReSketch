// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefClipboard.h"
#include <QBuffer>
#include <QClipboard>
#include <QEvent>
#include <QEventLoop>
#include <QGuiApplication>
#include <QImage>
#include <QMap>
#include <QMimeData>
#include <QPointer>
#include <QScopeGuard>
#include <QTimer>
#include <QUuid>
#include <QVariant>
#include <memory>
#undef signals
#include <gdk/gdkx.h>
#include <gtk/gtk.h>
#undef KeyPress

namespace {
class Bridge;
struct Target {
    GdkAtom atom;
    bool text = false;
};
struct Source {
    quint64 revision;
    QMap<QString, Target> targets;
    mutable QMap<QString, QByteArray> cache;
};
class ClipboardData final : public QMimeData {
  public:
    ClipboardData(Bridge *bridge, std::shared_ptr<Source> source);
    QStringList formats() const override;

  protected:
    QVariant retrieveData(const QString &format, QMetaType) const override;

  private:
    QPointer<Bridge> bridge;
    std::shared_ptr<Source> source;
};

// Qt owns the Wayland selection; GTK serves CEF's X11 selection. Figma copies
// remain lazy; external selections are snapshotted before replacing their X11
// owner, since that owner may itself be serving the Wayland offer via KWin.
class Bridge final : public QObject {
  public:
    GtkClipboard *x11 = nullptr;
    GdkDisplay *display = nullptr;
    GObject *owner = nullptr;
    QPointer<QMimeData> imported;
    QPointer<const QMimeData> lastExport;
    std::unique_ptr<QMimeData> exported;
    const QString marker = "application/x-resketch-clipboard-" + QUuid::createUuid().toString(QUuid::WithoutBraces);
    bool exporting = false, exportAgain = false;
    std::shared_ptr<Source> incoming;
    quint64 revision = 0;
    Bridge() {
        gdk_set_allowed_backends("x11");
        display = gdk_display_open(qgetenv("DISPLAY").constData());
        if (!display || !GDK_IS_X11_DISPLAY(display)) {
            qWarning("Cannot open the X11 clipboard bridge for the Wayland window");
            return;
        }
        x11 = gtk_clipboard_get_for_display(display, GDK_SELECTION_CLIPBOARD);
        owner = G_OBJECT(g_object_new(G_TYPE_OBJECT, nullptr));
        g_object_set_data(owner, "resketch-clipboard", this);
        g_signal_connect(x11, "owner-change", G_CALLBACK(+[](GtkClipboard *, GdkEventOwnerChange *, gpointer data) {
                             static_cast<Bridge *>(data)->fromX11();
                         }),
                         this);
        connect(QGuiApplication::clipboard(), &QClipboard::changed, this, [this](QClipboard::Mode mode) {
            if (mode == QClipboard::Clipboard)
                QTimer::singleShot(0, this, [this] { fromWayland(); });
        });
        connect(qGuiApp, &QGuiApplication::focusWindowChanged, this, [this] {
            if (!QGuiApplication::focusWindow())
                incoming.reset();
            QTimer::singleShot(0, this, [this] { fromWayland(); });
        });
        QTimer::singleShot(0, this, [this] { fromWayland(); });
        qGuiApp->installEventFilter(this);
    }
    bool eventFilter(QObject *, QEvent *event) override {
        // X11 copies already reach other Wayland apps through the compositor.
        // Publish our lazy local reader at the next input event: its fresh
        // Wayland serial is newer than the compositor's X11 selection serial.
        if (QGuiApplication::focusWindow() &&
            (event->type() == QEvent::KeyPress || event->type() == QEvent::MouseButtonPress)) {
            if (incoming && QGuiApplication::clipboard()->mimeData() != imported) {
                auto *data = new ClipboardData(this, incoming);
                imported = data;
                QGuiApplication::clipboard()->setMimeData(data);
            } else if (!incoming)
                fromWayland();
        }
        return false;
    }
    ~Bridge() override {
        if (x11) {
            g_signal_handlers_disconnect_by_data(x11, this);
            if (gtk_clipboard_get_owner(x11) == owner)
                gtk_clipboard_clear(x11);
        }
        if (owner)
            g_object_unref(owner);
        if (display)
            gdk_display_close(display);
    }
    void fromWayland() {
        if (!x11 || !QGuiApplication::focusWindow())
            return;
        QPointer<const QMimeData> mime = QGuiApplication::clipboard()->mimeData();
        if (!mime || dynamic_cast<const ClipboardData *>(mime.data()) || mime == imported || mime == lastExport ||
            mime->hasFormat(marker))
            return;
        if (incoming && !QGuiApplication::clipboard()->ownsClipboard())
            return;
        incoming.reset();
        if (exporting) {
            exportAgain = true;
            return;
        }
        exporting = true;
        const auto finish = qScopeGuard([this] {
            exporting = false;
            if (exportAgain) {
                exportAgain = false;
                QTimer::singleShot(0, this, [this] { fromWayland(); });
            }
        });
        ++revision;
        auto formats = mime->formats();
        if (mime->hasImage() && !formats.contains("image/png"))
            formats.append("image/png");
        if (mime->hasText())
            formats.append({"UTF8_STRING", "TEXT", "STRING", "text/plain;charset=utf-8"});
        formats.removeDuplicates();
        auto snapshot = std::make_unique<QMimeData>();
        for (const auto &format : mime->formats()) {
            if (format == "application/x-qt-image")
                snapshot->setImageData(mime->imageData());
            else
                snapshot->setData(format, mime->data(format));
            if (!mime || exportAgain)
                return;
        }
        if (mime->hasText())
            snapshot->setText(mime->text());
        if (!mime || exportAgain)
            return;
        lastExport = mime;
        exported = std::move(snapshot);
        if (formats.isEmpty()) {
            if (gtk_clipboard_get_owner(x11) == owner)
                gtk_clipboard_clear(x11);
            return;
        }
        formats.append(marker);
        QVector<QByteArray> names;
        for (const auto &format : formats)
            names.append(format.toUtf8());
        QVector<GtkTargetEntry> entries;
        for (auto &name : names)
            entries.append({name.data(), 0, 0});
        gtk_clipboard_set_with_owner(
            x11, entries.data(), entries.size(),
            +[](GtkClipboard *, GtkSelectionData *selection, guint, gpointer owner) {
                auto *self = static_cast<Bridge *>(g_object_get_data(G_OBJECT(owner), "resketch-clipboard"));
                QPointer<const QMimeData> mime = self ? self->exported.get() : nullptr;
                if (!mime)
                    return;
                gchar *name = gdk_atom_name(gtk_selection_data_get_target(selection));
                const QString format = QString::fromUtf8(name);
                g_free(name);
                if (format == "UTF8_STRING" || format == "TEXT" || format == "STRING" || format == "text/plain" ||
                    format == "text/plain;charset=utf-8") {
                    const auto text = mime->text().toUtf8();
                    gtk_selection_data_set_text(selection, text.constData(), text.size());
                } else {
                    auto bytes = mime->data(format);
                    if (format == "image/png" && bytes.isEmpty() && mime && mime->hasImage()) {
                        QBuffer buffer(&bytes);
                        buffer.open(QIODevice::WriteOnly);
                        qvariant_cast<QImage>(mime->imageData()).save(&buffer, "PNG");
                    }
                    gtk_selection_data_set(selection, gtk_selection_data_get_target(selection), 8,
                                           reinterpret_cast<const guchar *>(bytes.constData()), bytes.size());
                }
            },
            +[](GtkClipboard *, gpointer) {}, owner);
        gdk_display_flush(display);
    }
    void fromX11() {
        if (!QGuiApplication::focusWindow() || gtk_clipboard_get_owner(x11) == owner)
            return;
        incoming.reset();
        const auto current = ++revision;
        struct Request {
            QPointer<Bridge> bridge;
            quint64 revision;
        };
        gtk_clipboard_request_targets(
            x11,
            +[](GtkClipboard *, GdkAtom *atoms, gint count, gpointer data) {
                std::unique_ptr<Request> request(static_cast<Request *>(data));
                auto *self = request->bridge.data();
                if (!self || self->revision != request->revision || count <= 0)
                    return;
                QMap<QString, Target> targets;
                for (int i = 0; i < count; ++i) {
                    gchar *name = gdk_atom_name(atoms[i]);
                    QString format = QString::fromUtf8(name);
                    g_free(name);
                    if (QStringList{"TARGETS", "MULTIPLE", "TIMESTAMP", "SAVE_TARGETS", "DELETE", "INCR"}.contains(
                            format))
                        continue;
                    const bool text = format == "UTF8_STRING" || format == "STRING" || format == "TEXT" ||
                                      format == "text/plain" || format.startsWith("text/plain;charset=");
                    if (text) {
                        if (format != "UTF8_STRING" && targets.contains("text/plain"))
                            continue;
                        format = "text/plain";
                    }
                    targets[format] = {atoms[i], text};
                }
                if (targets.isEmpty())
                    return;
                self->incoming = std::make_shared<Source>(Source{request->revision, targets, {}});
            },
            new Request{this, current});
    }
};

ClipboardData::ClipboardData(Bridge *bridge, std::shared_ptr<Source> source)
    : bridge(bridge), source(std::move(source)) {}
QStringList ClipboardData::formats() const {
    auto names = source->targets.keys();
    if (source->targets.contains("text/plain"))
        names.append("text/plain;charset=utf-8");
    if (source->targets.contains("image/png"))
        names.append("application/x-qt-image");
    if (bridge)
        names.append(bridge->marker);
    return names;
}
QVariant ClipboardData::retrieveData(const QString &format, QMetaType) const {
    if (format == "application/x-qt-image")
        return QImage::fromData(data("image/png"));
    if (format == "text/plain;charset=utf-8")
        return data("text/plain");
    const auto source = this->source;
    const auto bridge = this->bridge;
    if (source->cache.contains(format))
        return source->cache[format];
    if (!bridge || bridge->revision != source->revision || !source->targets.contains(format))
        return {};
    struct Read {
        bool done = false;
        QByteArray bytes;
        QPointer<QEventLoop> loop;
    };
    auto read = std::make_shared<Read>();
    QEventLoop loop;
    read->loop = &loop;
    const auto target = source->targets.value(format);
    gtk_clipboard_request_contents(
        bridge->x11, target.atom,
        +[](GtkClipboard *, GtkSelectionData *selection, gpointer data) {
            std::unique_ptr<std::pair<std::shared_ptr<Read>, bool>> request(
                static_cast<std::pair<std::shared_ptr<Read>, bool> *>(data));
            auto &read = *request->first;
            const int size = gtk_selection_data_get_length(selection);
            if (size >= 0) {
                if (request->second) {
                    guchar *text = gtk_selection_data_get_text(selection);
                    if (text) {
                        read.bytes = QByteArray(reinterpret_cast<const char *>(text));
                        g_free(text);
                    }
                } else
                    read.bytes =
                        QByteArray(reinterpret_cast<const char *>(gtk_selection_data_get_data(selection)), size);
                read.done = true;
            }
            if (read.loop)
                read.loop->quit();
        },
        new std::pair{read, target.text});
    QTimer timeout;
    timeout.setSingleShot(true);
    QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
    timeout.start(5000);
    if (!read->done)
        loop.exec();
    // Qt may replace the Wayland offer while this asynchronous X11 read runs.
    // Keep the source/cache alive independently of that QMimeData wrapper.
    if (!read->done || !bridge || bridge->revision != source->revision)
        return {};
    source->cache[format] = read->bytes;
    return read->bytes;
}
std::unique_ptr<Bridge> bridge;
} // namespace

namespace ReSketchClipboard {
void initialize() {
    if (!bridge && QGuiApplication::platformName().startsWith("wayland"))
        bridge = std::make_unique<Bridge>();
}
void shutdown() { bridge.reset(); }
} // namespace ReSketchClipboard
