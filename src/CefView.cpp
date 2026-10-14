// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefView.h"
#include "CefApp.h"
#include "CefTexture.h"
#include "include/cef_client.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_dialog_handler.h"
#include "include/cef_parser.h"
#include "include/cef_permission_handler.h"
#include "include/cef_process_message.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QGuiApplication>
#include <QInputMethod>
#include <QJsonArray>
#include <QJsonDocument>
#include <QKeyEvent>
#include <QMenu>
#include <QMouseEvent>
#include <QOpenGLContext>
#include <QProcess>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSGSimpleRectNode>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QScreen>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTimer>
#include <QWheelEvent>
#include <chrono>
#include <cmath>

namespace {
struct Runtime {
    bool started = false, pumping = false, stopping = false;
    QTimer timer;
    CefRefPtr<ReSketchCefApp> app;
    quint16 debugPort = 0;
    std::map<int, CefRefPtr<CefBrowser>> browsers;
    Runtime() {
        timer.setSingleShot(true);
        QObject::connect(&timer, &QTimer::timeout, qApp, [this] {
            if (pumping || !started)
                return;
            pumping = true;
            CefDoMessageLoopWork();
            pumping = false;
            // As in CEF's external-pump example, poll idle work too: Chromium
            // does not schedule every native X11/GLib event through this hook.
            if (!timer.isActive())
                timer.start(33);
        });
    }
    void schedule(int64_t delay) {
        QMetaObject::invokeMethod(
            qApp,
            [this, delay] {
                if (!started)
                    return;
                const int ms = int(std::clamp<int64_t>(delay, 0, 33));
                if (!timer.isActive() || timer.remainingTime() > ms)
                    timer.start(ms);
            },
            Qt::QueuedConnection);
    }
};
Runtime &runtime() {
    static Runtime value;
    return value;
}
QString runtimeDirectory() {
    const QDir app(QCoreApplication::applicationDirPath());
    const QString installed = app.filePath("../lib/ReSketch/cef");
    if (QFileInfo::exists(installed + "/libcef.so"))
        return QDir(installed).absolutePath();
#ifdef RESKETCH_CEF_RUNTIME
    return QStringLiteral(RESKETCH_CEF_RUNTIME);
#else
    return app.filePath("cef");
#endif
}
std::string utf8(const QString &text) { return text.toUtf8().toStdString(); }
QString text(const CefString &value) { return QString::fromStdString(value.ToString()); }
CefRefPtr<CefDictionaryValue> dictionary(const QJsonObject &value) {
    const auto parsed = CefParseJSON(
        utf8(QString::fromUtf8(QJsonDocument(value).toJson(QJsonDocument::Compact))), JSON_PARSER_RFC);
    return parsed ? parsed->GetDictionary() : CefDictionaryValue::Create();
}
uint32_t modifiers(Qt::KeyboardModifiers keys, Qt::MouseButtons buttons = {}) {
    uint32_t result = 0;
    if (keys.testFlag(Qt::ShiftModifier))
        result |= EVENTFLAG_SHIFT_DOWN;
    if (keys.testFlag(Qt::ControlModifier))
        result |= EVENTFLAG_CONTROL_DOWN;
    if (keys.testFlag(Qt::AltModifier))
        result |= EVENTFLAG_ALT_DOWN;
    if (keys.testFlag(Qt::MetaModifier))
        result |= EVENTFLAG_COMMAND_DOWN;
    if (keys.testFlag(Qt::KeypadModifier))
        result |= EVENTFLAG_IS_KEY_PAD;
    if (buttons.testFlag(Qt::LeftButton))
        result |= EVENTFLAG_LEFT_MOUSE_BUTTON;
    if (buttons.testFlag(Qt::RightButton))
        result |= EVENTFLAG_RIGHT_MOUSE_BUTTON;
    if (buttons.testFlag(Qt::MiddleButton))
        result |= EVENTFLAG_MIDDLE_MOUSE_BUTTON;
    return result;
}
CefMouseEvent mouse(QPointF point, Qt::KeyboardModifiers keys, Qt::MouseButtons buttons = {}) {
    CefMouseEvent event;
    event.x = qRound(point.x());
    event.y = qRound(point.y());
    event.modifiers = modifiers(keys, buttons);
    return event;
}
CefBrowserHost::MouseButtonType button(Qt::MouseButton value) {
    return value == Qt::RightButton ? MBT_RIGHT : value == Qt::MiddleButton ? MBT_MIDDLE : MBT_LEFT;
}
int keyCode(int key) {
    if (key >= Qt::Key_F1 && key <= Qt::Key_F24)
        return 0x70 + key - Qt::Key_F1;
    if (key >= Qt::Key_A && key <= Qt::Key_Z)
        return key;
    if (key >= Qt::Key_0 && key <= Qt::Key_9)
        return key;
    switch (key) {
    case Qt::Key_Backspace:
        return 0x08;
    case Qt::Key_Tab:
    case Qt::Key_Backtab:
        return 0x09;
    case Qt::Key_Return:
    case Qt::Key_Enter:
        return 0x0D;
    case Qt::Key_Shift:
        return 0x10;
    case Qt::Key_Control:
        return 0x11;
    case Qt::Key_Alt:
        return 0x12;
    case Qt::Key_Escape:
        return 0x1B;
    case Qt::Key_Space:
        return 0x20;
    case Qt::Key_PageUp:
        return 0x21;
    case Qt::Key_PageDown:
        return 0x22;
    case Qt::Key_End:
        return 0x23;
    case Qt::Key_Home:
        return 0x24;
    case Qt::Key_Left:
        return 0x25;
    case Qt::Key_Up:
        return 0x26;
    case Qt::Key_Right:
        return 0x27;
    case Qt::Key_Down:
        return 0x28;
    case Qt::Key_Insert:
        return 0x2D;
    case Qt::Key_Delete:
        return 0x2E;
    case Qt::Key_Meta:
        return 0x5B;
    case Qt::Key_Semicolon:
    case Qt::Key_Colon:
        return 0xBA;
    case Qt::Key_Equal:
    case Qt::Key_Plus:
        return 0xBB;
    case Qt::Key_Comma:
    case Qt::Key_Less:
        return 0xBC;
    case Qt::Key_Minus:
    case Qt::Key_Underscore:
        return 0xBD;
    case Qt::Key_Period:
    case Qt::Key_Greater:
        return 0xBE;
    case Qt::Key_Slash:
    case Qt::Key_Question:
        return 0xBF;
    case Qt::Key_QuoteLeft:
    case Qt::Key_AsciiTilde:
        return 0xC0;
    case Qt::Key_BracketLeft:
    case Qt::Key_BraceLeft:
        return 0xDB;
    case Qt::Key_Backslash:
    case Qt::Key_Bar:
        return 0xDC;
    case Qt::Key_BracketRight:
    case Qt::Key_BraceRight:
        return 0xDD;
    case Qt::Key_Apostrophe:
    case Qt::Key_QuoteDbl:
        return 0xDE;
    default:
        return key & 0xFFFF;
    }
}
struct ViewNode : QSGNode {
    QSGSimpleRectNode background;
    QSGSimpleTextureNode *page = nullptr, *popup = nullptr;
    std::shared_ptr<CefTextureFrame> pageFrame, popupFrame;
    QImage pageImage, popupImage;
    ViewNode() { appendChildNode(&background); }
    ~ViewNode() { removeChildNode(&background); }
};
void setTexture(QQuickWindow *window, ViewNode *root, QSGSimpleTextureNode *&node,
                std::shared_ptr<CefTextureFrame> &previous, QImage &previousImage,
                const std::shared_ptr<CefTextureFrame> &frame, const QImage &image) {
    if (frame == previous && image.cacheKey() == previousImage.cacheKey())
        return;
    QSGTexture *texture = nullptr;
    if (frame && window->rendererInterface()->graphicsApi() == QSGRendererInterface::OpenGL)
        texture = QNativeInterface::QSGOpenGLTexture::fromNative(frame->texture, window, frame->size,
                                                                 QQuickWindow::TextureHasAlphaChannel);
    else if (!image.isNull())
        texture = window->createTextureFromImage(image);
    if (!texture) {
        if (node) {
            root->removeChildNode(node);
            delete node;
            node = nullptr;
        }
        previous.reset();
        previousImage = {};
        return;
    }
    if (!node) {
        node = new QSGSimpleTextureNode;
        node->setTexture(texture);
        node->setOwnsTexture(true);
        root->appendChildNode(node);
    } else
        node->setTexture(texture);
    previous = frame;
    previousImage = image;
    node->setFiltering(QSGTexture::Linear);
}
} // namespace
namespace ReSketchCef {
bool initialized() { return runtime().started; }
void initialize(const QStringList &switches) {
    auto &state = runtime();
    if (state.started)
        return;
    const QString directory = runtimeDirectory();
    const QString helper = qEnvironmentVariableIsSet("RESKETCH_CEF_HELPER")
                               ? qEnvironmentVariable("RESKETCH_CEF_HELPER")
                               : QDir(QCoreApplication::applicationDirPath()).filePath("resketch-cef-helper");
    if (!QFileInfo::exists(helper))
        qFatal("CEF subprocess executable is missing: %s", qPrintable(helper));
    CefSettings settings;
    settings.windowless_rendering_enabled = true;
    settings.external_message_pump = true;
    CefString(&settings.browser_subprocess_path) = utf8(helper);
    CefString(&settings.resources_dir_path) = utf8(directory);
    CefString(&settings.locales_dir_path) = utf8(directory + "/locales");
    const QString cache =
        qEnvironmentVariableIsSet("RESKETCH_CEF_CACHE_ROOT")
            ? qEnvironmentVariable("RESKETCH_CEF_CACHE_ROOT")
            : QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/ReSketch/CEF";
    QDir().mkpath(cache);
    CefString(&settings.root_cache_path) = utf8(cache);
    CefString(&settings.log_file) = utf8(cache + "/cef.log");
    settings.log_severity = LOGSEVERITY_WARNING;
    std::vector<std::string> flags;
    for (const auto &flag : switches)
        flags.push_back(utf8(flag));
    if (flags.empty())
        for (const auto &flag : QProcess::splitCommand(qEnvironmentVariable("RESKETCH_CEF_FLAGS")))
            flags.push_back(utf8(flag));
    for (const auto &flag : flags) {
        if (flag == "--no-sandbox")
            settings.no_sandbox = true;
        if (flag.starts_with("--remote-debugging-port="))
            settings.remote_debugging_port = std::stoi(flag.substr(24));
    }
    // CEF's native DevTools popup cannot use windowless rendering. Keep its
    // frontend in our Kirigami window via Chromium's loopback-only endpoint.
    if (!settings.remote_debugging_port) {
        QTcpServer reservation;
        if (!reservation.listen(QHostAddress::LocalHost, 0))
            qFatal("Cannot reserve the local Developer Tools port");
        settings.remote_debugging_port = reservation.serverPort();
    }
    state.debugPort = settings.remote_debugging_port;
    state.app = new ReSketchCefApp(std::move(flags), [&state](int64_t delay) { state.schedule(delay); });
    int argc = 1;
    QByteArray name = QCoreApplication::applicationFilePath().toUtf8();
    char *argv[]{name.data(), nullptr};
    if (!CefInitialize(CefMainArgs(argc, argv), settings, state.app, nullptr))
        qFatal("CEF initialization failed");
    state.started = true;
    state.schedule(0);
    qAddPostRoutine(ReSketchCef::shutdown);
}
void browserCreated(CefRefPtr<CefBrowser> browser) { runtime().browsers[browser->GetIdentifier()] = browser; }
void browserClosed(int id) { runtime().browsers.erase(id); }
void shutdown() {
    auto &state = runtime();
    if (!state.started)
        return;
    state.stopping = true;
    {
        const auto browsers = state.browsers;
        for (const auto &[id, browser] : browsers)
            browser->GetHost()->CloseBrowser(true);
    }
    const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (!state.browsers.empty() && std::chrono::steady_clock::now() < until) {
        CefDoMessageLoopWork();
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    }
    state.timer.stop();
    state.browsers.clear();
    state.app = nullptr;
    CefShutdown();
    state.started = false;
}
} // namespace ReSketchCef

class CefQuickClient final : public CefClient,
                             public CefRenderHandler,
                             public CefLifeSpanHandler,
                             public CefDisplayHandler,
                             public CefLoadHandler,
                             public CefRequestHandler,
                             public CefDownloadHandler,
                             public CefPermissionHandler,
                             public CefDialogHandler,
                             public CefContextMenuHandler,
                             public CefDevToolsMessageObserver {
  public:
    explicit CefQuickClient(CefQuickView *view) : view(view) {}
    CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
    CefRefPtr<CefDialogHandler> GetDialogHandler() override { return this; }
    CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
    bool current(CefRefPtr<CefBrowser> browser) const {
        return view && view->m_browser && browser->IsSame(view->m_browser);
    }
    void GetViewRect(CefRefPtr<CefBrowser>, CefRect &rect) override {
        rect = CefRect(0, 0, view ? std::max(1, qRound(view->width())) : 1,
                       view ? std::max(1, qRound(view->height())) : 1);
    }
    bool GetScreenInfo(CefRefPtr<CefBrowser>, CefScreenInfo &info) override {
        if (!view)
            return false;
        auto *screen = view->window() ? view->window()->screen() : QGuiApplication::primaryScreen();
        info.device_scale_factor = view->window() ? view->window()->devicePixelRatio() : 1;
        const auto rect = screen ? screen->geometry() : QRect(0, 0, 1280, 800);
        info.rect = CefRect(rect.x(), rect.y(), rect.width(), rect.height());
        const auto available = screen ? screen->availableGeometry() : rect;
        info.available_rect = CefRect(available.x(), available.y(), available.width(), available.height());
        return true;
    }
    bool GetScreenPoint(CefRefPtr<CefBrowser>, int x, int y, int &sx, int &sy) override {
        if (!view)
            return false;
        const auto point = view->mapToGlobal(QPointF(x, y));
        const double scale = view->window() ? view->window()->devicePixelRatio() : 1;
        sx = qRound(point.x() * scale);
        sy = qRound(point.y() * scale);
        return true;
    }
    bool GetRootScreenRect(CefRefPtr<CefBrowser>, CefRect &rect) override {
        if (!view || !view->window())
            return false;
        const auto r = view->window()->geometry();
        rect = CefRect(r.x(), r.y(), r.width(), r.height());
        return true;
    }
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        ReSketchCef::browserCreated(browser);
        // Closing from OnAfterCreated can destroy CEF's platform delegate before
        // its creation notification completes. Retire cancelled views next turn.
        if (!view || view->m_closing || view->m_client.get() != this) {
            QTimer::singleShot(0, qApp, [browser] { browser->GetHost()->CloseBrowser(true); });
            return;
        }
        view->m_creating = false;
        view->m_browser = browser;
        view->m_client = this;
        view->m_observer = browser->GetHost()->AddDevToolsMessageObserver(this);
        browser->GetHost()->SetFocus(view->hasActiveFocus());
        view->syncVisibility();
        view->syncScreen();
        QTimer::singleShot(0, view, [target = view, browser] {
            if (!target || !target->m_browser || !browser->IsSame(target->m_browser))
                return;
            if (!target->m_pendingAddress.isEmpty()) {
                browser->GetMainFrame()->LoadURL(utf8(target->m_pendingAddress));
                target->m_pendingAddress.clear();
            }
            if (target->m_lifecycle != CefQuickView::LifecycleState::Active)
                target->setLifecycleState(target->m_lifecycle);
        });
    }
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        if (current(browser)) {
            view->m_observer = nullptr;
            view->m_browser = nullptr;
            view->m_pid = 0;
            emit view->renderProcessPidChanged();
        }
        ReSketchCef::browserClosed(browser->GetIdentifier());
    }
    bool DoClose(CefRefPtr<CefBrowser> browser) override {
        if (current(browser) && !view->m_closing)
            emit view->windowCloseRequested();
        return false;
    }
    bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, int, const CefString &url,
                       const CefString &, cef_window_open_disposition_t where, bool, const CefPopupFeatures &,
                       CefWindowInfo &info, CefRefPtr<CefClient> &client, CefBrowserSettings &settings,
                       CefRefPtr<CefDictionaryValue> &extra, bool *) override {
        if (!current(browser))
            return true;
        CefNewWindowRequest request(QUrl(text(url)), where == CEF_WOD_NEW_BACKGROUND_TAB
                                                         ? CefNewWindowRequest::InNewBackgroundTab
                                                         : CefNewWindowRequest::InNewTab);
        emit view->newWindowRequested(&request);
        if (!request.target)
            return true;
        auto *target = request.target;
        target->m_creating = true;
        target->m_client = new CefQuickClient(target);
        info.SetAsWindowless(0);
        info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
        info.shared_texture_enabled = cefSharedTexturesSupported();
        settings.background_color = CefColorSetARGB(0, 0, 0, 0);
        settings.windowless_frame_rate = 60;
        client = target->m_client;
        extra = target->extraInfo();
        return false;
    }
    bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefRequest> request, bool, bool) override {
        if (!current(browser))
            return false;
        const QUrl address(text(request->GetURL()));
        if (address.toString() == view->m_htmlAddress)
            return false;
        CefNavigationRequest navigation(address, frame->IsMain());
        emit view->navigationRequested(&navigation);
        return navigation.rejected;
    }
    bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, const CefString &url,
                          cef_window_open_disposition_t where, bool) override {
        if (!current(browser))
            return false;
        CefNewWindowRequest request(QUrl(text(url)), where == CEF_WOD_NEW_BACKGROUND_TAB
                                                         ? CefNewWindowRequest::InNewBackgroundTab
                                                         : CefNewWindowRequest::InNewTab);
        emit view->newWindowRequested(&request);
        if (request.target)
            request.target->setUrl(request.requestedUrl);
        return true;
    }
    void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                         const CefString &url) override {
        if (!current(browser) || !frame->IsMain())
            return;
        const QUrl address(text(url));
        if (address.toString() == view->m_htmlAddress)
            return;
        if (view->m_url != address) {
            view->m_url = address;
            emit view->urlChanged();
        }
    }
    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
        if (!current(browser))
            return;
        view->m_title = text(title);
        emit view->titleChanged();
    }
    void OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) override {
        if (!current(browser))
            return;
        view->m_progress = qRound(progress * 100);
        emit view->loadProgressChanged();
    }
    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool loading, bool, bool) override {
        if (!current(browser))
            return;
        view->m_loading = loading;
        emit view->stateChanged();
        emit view->loadStateChanged(
            {{"status", loading ? CefQuickView::LoadStartedStatus : CefQuickView::LoadSucceededStatus}});
    }
    void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, ErrorCode code,
                     const CefString &error, const CefString &) override {
        if (!current(browser) || !frame->IsMain() || code == ERR_ABORTED)
            return;
        view->m_loading = false;
        emit view->stateChanged();
        emit view->loadStateChanged(
            {{"status", CefQuickView::LoadFailedStatus}, {"errorString", text(error)}});
    }
    void OnPaint(CefRefPtr<CefBrowser> browser, PaintElementType type, const RectList &, const void *buffer,
                 int width, int height) override {
        if (!current(browser))
            return;
        view->publishFrame(QImage(static_cast<const uchar *>(buffer), width, height, width * 4,
                                  QImage::Format_ARGB32_Premultiplied)
                               .copy(),
                           type == PET_POPUP);
    }
    void OnAcceleratedPaint(CefRefPtr<CefBrowser> browser, PaintElementType type, const RectList &,
                            const CefAcceleratedPaintInfo &info) override {
        if (current(browser))
            view->publishAccelerated(info, type == PET_POPUP);
    }
    void OnPopupShow(CefRefPtr<CefBrowser> browser, bool show) override {
        if (current(browser)) {
            QMutexLocker lock(&view->m_frameMutex);
            view->m_popupVisible = show;
            view->update();
        }
    }
    void OnPopupSize(CefRefPtr<CefBrowser> browser, const CefRect &rect) override {
        if (current(browser)) {
            QMutexLocker lock(&view->m_frameMutex);
            view->m_popupRect = QRect(rect.x, rect.y, rect.width, rect.height);
            view->update();
        }
    }
    bool OnCursorChange(CefRefPtr<CefBrowser> browser, CefCursorHandle, cef_cursor_type_t type,
                        const CefCursorInfo &) override {
        if (!current(browser))
            return false;
        Qt::CursorShape cursor = Qt::ArrowCursor;
        if (type == CT_HAND)
            cursor = Qt::PointingHandCursor;
        else if (type == CT_IBEAM)
            cursor = Qt::IBeamCursor;
        else if (type == CT_CROSS)
            cursor = Qt::CrossCursor;
        else if (type == CT_MOVE)
            cursor = Qt::SizeAllCursor;
        else if (type == CT_EASTWESTRESIZE)
            cursor = Qt::SizeHorCursor;
        else if (type == CT_NORTHSOUTHRESIZE)
            cursor = Qt::SizeVerCursor;
        else if (type == CT_NONE)
            cursor = Qt::BlankCursor;
        view->setCursor(cursor);
        return true;
    }
    void OnImeCompositionRangeChanged(CefRefPtr<CefBrowser> browser, const CefRange &,
                                      const RectList &bounds) override {
        if (current(browser) && !bounds.empty()) {
            const auto &r = bounds.front();
            view->m_imeRect = QRect(r.x, r.y, r.width, r.height);
            QGuiApplication::inputMethod()->update(Qt::ImCursorRectangle);
        }
    }
    bool OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser, uint64_t, const CefString &origin,
                                uint32_t requested,
                                CefRefPtr<CefPermissionPromptCallback> callback) override {
        if (!current(browser)) {
            callback->Continue(CEF_PERMISSION_RESULT_DENY);
            return true;
        }
        const uint32_t allowedMask = CEF_PERMISSION_TYPE_NOTIFICATIONS | CEF_PERMISSION_TYPE_CLIPBOARD |
                                     CEF_PERMISSION_TYPE_LOCAL_FONTS | CEF_PERMISSION_TYPE_LOOPBACK_NETWORK |
                                     CEF_PERMISSION_TYPE_LOCAL_NETWORK;
        bool accepted = (requested & ~allowedMask) == 0;
        const std::vector<std::pair<uint32_t, CefPermission::PermissionType>> types{
            {CEF_PERMISSION_TYPE_NOTIFICATIONS, CefPermission::PermissionType::Notifications},
            {CEF_PERMISSION_TYPE_CLIPBOARD, CefPermission::PermissionType::ClipboardReadWrite},
            {CEF_PERMISSION_TYPE_LOCAL_FONTS, CefPermission::PermissionType::LocalFontsAccess},
            {CEF_PERMISSION_TYPE_LOOPBACK_NETWORK | CEF_PERMISSION_TYPE_LOCAL_NETWORK,
             CefPermission::PermissionType::LocalNetworkAccess}};
        for (const auto &[mask, type] : types)
            if (requested & mask) {
                CefPermission permission(QUrl(text(origin)), type);
                emit view->permissionRequested(&permission);
                accepted &= permission.accepted;
            }
        callback->Continue(accepted ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY);
        return true;
    }
    bool OnBeforeDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                          const CefString &name, CefRefPtr<CefBeforeDownloadCallback> callback) override {
        if (!current(browser) || !view->profile())
            return true;
        auto *profile = view->profile();
        auto *download = new CefDownload(profile);
        download->source = view;
        download->id = item->GetId();
        download->url = QUrl(text(item->GetURL()));
        download->suggestedFileName = QFileInfo(text(name)).fileName();
        download->downloadFileName = download->suggestedFileName;
        download->start = callback;
        profile->downloads[download->id] = download;
        emit profile->downloadRequested(download);
        if (download->state == CefDownload::DownloadRequested)
            download->cancel();
        return true;
    }
    void OnDownloadUpdated(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem> item,
                           CefRefPtr<CefDownloadItemCallback> callback) override {
        if (!view || !view->profile())
            return;
        auto *profile = view->profile();
        auto *download = profile->downloads.value(item->GetId()).data();
        if (!download)
            return;
        download->progress = callback;
        const QFileInfo file(text(item->GetFullPath()));
        if (!file.fileName().isEmpty()) {
            download->downloadDirectory = file.absolutePath();
            download->downloadFileName = file.fileName();
        }
        if (item->IsComplete())
            download->state = CefDownload::DownloadCompleted;
        else if (item->IsCanceled())
            download->state = CefDownload::DownloadCancelled;
        else if (!item->IsInProgress())
            download->state = CefDownload::DownloadInterrupted;
        else
            download->state = CefDownload::DownloadInProgress;
        emit download->changed();
        if (download->state != CefDownload::DownloadInProgress) {
            emit profile->downloadFinished(download);
            profile->downloads.remove(download->id);
            download->deleteLater();
        }
    }
    bool OnFileDialog(CefRefPtr<CefBrowser> browser, FileDialogMode mode, const CefString &title,
                      const CefString &path, const std::vector<CefString> &filters,
                      const std::vector<CefString> &, const std::vector<CefString> &,
                      CefRefPtr<CefFileDialogCallback> callback) override {
        if (!current(browser)) {
            callback->Cancel();
            return true;
        }
        QStringList names;
        for (const auto &filter : filters) {
            const auto f = text(filter);
            if (f.startsWith('.'))
                names << "*" + f;
        }
        QStringList selected;
        const int kind = int(mode) & 0xFF;
        if (kind == FILE_DIALOG_OPEN_MULTIPLE)
            selected = QFileDialog::getOpenFileNames(nullptr, text(title), text(path), names.join(' '));
        else if (kind == FILE_DIALOG_OPEN_FOLDER) {
            const auto folder = QFileDialog::getExistingDirectory(nullptr, text(title), text(path));
            if (!folder.isEmpty())
                selected << folder;
        } else if (kind == FILE_DIALOG_SAVE) {
            const auto file = QFileDialog::getSaveFileName(nullptr, text(title), text(path), names.join(' '));
            if (!file.isEmpty())
                selected << file;
        } else {
            const auto file = QFileDialog::getOpenFileName(nullptr, text(title), text(path), names.join(' '));
            if (!file.isEmpty())
                selected << file;
        }
        std::vector<CefString> files;
        for (const auto &file : selected)
            files.push_back(utf8(file));
        if (files.empty())
            callback->Cancel();
        else
            callback->Continue(files);
        return true;
    }
    bool RunContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>,
                        CefRefPtr<CefContextMenuParams> params, CefRefPtr<CefMenuModel> model,
                        CefRefPtr<CefRunContextMenuCallback> callback) override {
        if (!current(browser)) {
            callback->Cancel();
            return true;
        }
        auto *menu = new QMenu;
        const auto point = view->mapToGlobal(QPointF(params->GetXCoord(), params->GetYCoord()));
        auto chosen = std::make_shared<bool>(false);
        const auto add = [callback, chosen](const auto &self, QMenu *menu,
                                            CefRefPtr<CefMenuModel> model) -> void {
            for (size_t i = 0; i < model->GetCount(); ++i) {
                if (model->GetTypeAt(i) == MENUITEMTYPE_SEPARATOR) {
                    menu->addSeparator();
                    continue;
                }
                if (model->GetTypeAt(i) == MENUITEMTYPE_SUBMENU) {
                    self(self, menu->addMenu(text(model->GetLabelAt(i))), model->GetSubMenuAt(i));
                    continue;
                }
                const int id = model->GetCommandIdAt(i);
                auto *action = menu->addAction(text(model->GetLabelAt(i)));
                action->setEnabled(model->IsEnabledAt(i));
                action->setCheckable(model->GetTypeAt(i) == MENUITEMTYPE_CHECK ||
                                     model->GetTypeAt(i) == MENUITEMTYPE_RADIO);
                action->setChecked(model->IsCheckedAt(i));
                QObject::connect(action, &QAction::triggered, menu, [callback, chosen, id] {
                    *chosen = true;
                    callback->Continue(id, EVENTFLAG_NONE);
                });
            }
        };
        add(add, menu, model);
        QObject::connect(menu, &QMenu::aboutToHide, menu, [menu, callback, chosen] {
            if (!*chosen)
                callback->Cancel();
            menu->deleteLater();
        });
        menu->popup(point.toPoint());
        return true;
    }
    void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser, int id, bool success, const void *data,
                                size_t size) override {
        if (!current(browser))
            return;
        const auto json =
            QJsonDocument::fromJson(QByteArray(static_cast<const char *>(data), int(size))).object();
        // Browser-side methods can reply inside ExecuteDevToolsMethod before
        // it returns the assigned ID. Deliver after callers register callbacks.
        QTimer::singleShot(0, view, [target = view, id, success, json] {
            if (!target)
                return;
            if (auto native = target->m_protocolCallbacks.take(id)) {
                native(success ? json : QJsonObject{});
                return;
            }
            const auto callback = target->m_callbacks.take(id);
            if (!callback.isCallable())
                return;
            const auto result =
                success ? json.value("result").toObject().value("value").toVariant() : QVariant{};
            if (auto *engine = qjsEngine(target))
                callback.call({engine->toScriptValue(result)});
        });
    }
    bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, CefProcessId,
                                  CefRefPtr<CefProcessMessage> message) override {
        if (!current(browser))
            return false;
        const auto args = message->GetArgumentList();
        if (message->GetName() == "resketch.renderer") {
            view->m_pid = args->GetInt(0);
            emit view->renderProcessPidChanged();
            return true;
        }
        if (message->GetName() != "resketch.bridge")
            return false;
        const auto origin = QUrl(text(args->GetString(2)));
        const auto host = origin.host();
        if (!view->property("notificationSource").toBool() || origin.scheme() != "https" ||
            !(host == "figma.com" || host.endsWith(".figma.com")))
            return true;
        if (args->GetString(0) == "notification" && view->profile()) {
            const auto value =
                QJsonDocument::fromJson(QByteArray::fromStdString(args->GetString(1).ToString())).object();
            auto *notice =
                new CefNotification(value["title"].toString().left(256), value["body"].toString().left(2000),
                                    origin, value["id"].toString(), view);
            const QString id = value["id"].toString();
            view->m_notifications[id] = notice;
            QObject::connect(notice, &CefNotification::closed, view, [target = view, id] {
                if (target)
                    target->m_notifications.remove(id);
            });
            emit view->profile()->presentNotification(notice);
        } else if (args->GetString(0) == "close-notification") {
            if (auto notice = view->m_notifications.value(text(args->GetString(1))))
                notice->close();
        }
        return true;
    }

  private:
    QPointer<CefQuickView> view;
    IMPLEMENT_REFCOUNTING(CefQuickClient);
};

CefPermission::CefPermission(QUrl origin, PermissionType type, QObject *parent)
    : QObject(parent), m_origin(origin), m_type(type) {}
CefNotification::CefNotification(QString title, QString message, QUrl origin, QString id, CefQuickView *view)
    : QObject(view), m_title(title), m_message(message), m_id(id), m_origin(origin), m_view(view) {}
void CefNotification::show() {
    if (m_view)
        m_view->executeNotificationEvent(m_id, "show");
}
void CefNotification::close() {
    if (m_closed)
        return;
    m_closed = true;
    if (m_view)
        m_view->executeNotificationEvent(m_id, "close");
    emit closed();
    deleteLater();
}
void CefNotification::click() {
    if (m_view)
        m_view->executeNotificationEvent(m_id, "click");
}
QObject *CefDownload::view() const { return source; }
void CefDownload::accept() {
    if (!start || state != DownloadRequested)
        return;
    QDir().mkpath(downloadDirectory);
    state = DownloadInProgress;
    start->Continue(utf8(QDir(downloadDirectory).filePath(downloadFileName)), false);
    start = nullptr;
    emit changed();
}
void CefDownload::cancel() {
    if (progress)
        progress->Cancel();
    start = nullptr;
    state = DownloadCancelled;
    emit changed();
}
CefProfile::CefProfile(QObject *parent) : QObject(parent) {}
CefRefPtr<CefRequestContext> CefProfile::context() {
    if (m_context)
        return m_context;
    ReSketchCef::initialize();
    CefRequestContextSettings settings;
    if (!offTheRecord && !persistentStoragePath.isEmpty()) {
        QDir().mkpath(persistentStoragePath);
        CefString(&settings.cache_path) = utf8(persistentStoragePath);
        settings.persist_session_cookies = true;
    }
    m_context = CefRequestContext::CreateContext(settings, nullptr);
    return m_context;
}
CefPermission *CefProfile::queryPermission(const QUrl &origin, CefPermission::PermissionType type) {
    const QString key = origin.toString() + QLatin1Char('/') + QString::number(int(type));
    auto &permission = m_permissions[key];
    if (!permission)
        permission = new CefPermission(origin, type, this);
    return permission;
}

CefQuickView::CefQuickView(QQuickItem *parent) : QQuickItem(parent), m_scripts(this), m_settings(this) {
    setFlag(ItemHasContents);
    setFlag(ItemAcceptsInputMethod);
    setAcceptedMouseButtons(Qt::AllButtons);
    setAcceptHoverEvents(true);
    connect(&m_scripts, &CefScriptCollection::changed, this, &CefQuickView::syncScripts);
    connect(this, &QQuickItem::windowChanged, this, [this] {
        disconnect(m_screenConnection);
        if (window())
            m_screenConnection = connect(window(), &QWindow::screenChanged, this, [this] { syncScreen(); });
        syncScreen();
    });
}
CefQuickView::~CefQuickView() {
    m_closing = true;
    if (m_inspected && m_inspected->m_devTools == this) {
        m_inspected->m_devTools = nullptr;
        emit m_inspected->devToolsViewChanged();
    }
    m_observer = nullptr;
    m_callbacks.clear();
    if (m_browser)
        m_browser->GetHost()->CloseBrowser(true);
    m_browser = nullptr;
    m_client = nullptr;
}
void CefQuickView::setUrl(const QUrl &value) {
    if (m_url == value)
        return;
    m_url = value;
    m_htmlAddress.clear();
    emit urlChanged();
    if (m_lifecycle != LifecycleState::Discarded) {
        ensureBrowser();
        if (m_browser)
            m_browser->GetMainFrame()->LoadURL(utf8(m_url.toString()));
        else if (m_creating)
            m_pendingAddress = m_url.toString();
    }
}
void CefQuickView::setProfile(CefProfile *value) {
    if (m_profile == value)
        return;
    m_profile = value;
    emit profileChanged();
}
void CefQuickView::setInspectedView(CefQuickView *value) {
    if (m_inspected == value)
        return;
    if (m_inspected && m_inspected->m_devTools == this) {
        m_inspected->m_devTools = nullptr;
        emit m_inspected->devToolsViewChanged();
    }
    m_inspected = value;
    emit inspectedViewChanged();
    if (!value) {
        setLifecycleState(LifecycleState::Discarded);
        return;
    }
    value->m_devTools = this;
    emit value->devToolsViewChanged();
    if (!value->browser())
        return;
    const int id = value->browser()->GetHost()->ExecuteDevToolsMethod(0, "Target.getTargetInfo", nullptr);
    value->m_protocolCallbacks[id] = [target = QPointer<CefQuickView>(this),
                                      source = QPointer<CefQuickView>(value)](const QJsonObject &result) {
        if (!target || target->m_inspected != source)
            return;
        const QString identifier = result.value("targetInfo").toObject().value("targetId").toString();
        if (identifier.isEmpty())
            return;
        target->setUrl(
            QUrl(QStringLiteral("devtools://devtools/bundled/inspector.html?ws=127.0.0.1:%1/devtools/page/%2")
                     .arg(runtime().debugPort)
                     .arg(identifier)));
        target->setLifecycleState(LifecycleState::Active);
    };
}
void CefQuickView::setBackgroundColor(const QColor &value) {
    if (m_background == value)
        return;
    m_background = value;
    emit backgroundColorChanged();
    update();
}
void CefQuickView::ensureBrowser() {
    if (m_browser || m_creating || m_closing || m_url.isEmpty() || m_lifecycle == LifecycleState::Discarded)
        return;
    ReSketchCef::initialize();
    if (!m_profile) {
        auto *profile = new CefProfile(this);
        profile->offTheRecord = true;
        setProfile(profile);
    }
    CefWindowInfo info;
    info.SetAsWindowless(0);
    info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
    info.shared_texture_enabled = cefSharedTexturesSupported();
    CefBrowserSettings settings;
    settings.background_color = CefColorSetARGB(0, 0, 0, 0);
    settings.windowless_frame_rate =
        window() && window()->screen() ? qBound(1, qRound(window()->screen()->refreshRate()), 240) : 60;
    m_client = new CefQuickClient(this);
    m_creating = true;
    m_loading = true;
    m_progress = 0;
    emit stateChanged();
    emit loadProgressChanged();
    if (!CefBrowserHost::CreateBrowser(info, m_client, utf8(m_url.toString()), settings, extraInfo(),
                                       m_profile->context()))
        m_creating = false;
}
CefRefPtr<CefDictionaryValue> CefQuickView::extraInfo() const {
    QJsonArray scripts;
    for (const auto &script : m_scripts.collection())
        scripts.append(QJsonObject::fromVariantMap(script.toMap()));
    return dictionary({{"scripts", scripts}});
}
void CefQuickView::syncScripts() {
    if (!m_browser)
        return;
    auto message = CefProcessMessage::Create("resketch.scripts");
    message->GetArgumentList()->SetList(0, extraInfo()->GetList("scripts"));
    m_browser->GetMainFrame()->SendProcessMessage(PID_RENDERER, message);
}
int CefQuickView::devTools(const QString &method, const QJsonObject &params, QJSValue callback) {
    if (!m_browser) {
        if (callback.isCallable())
            callback.call({QJSValue()});
        return 0;
    }
    const int id = m_browser->GetHost()->ExecuteDevToolsMethod(0, utf8(method), dictionary(params));
    if (callback.isCallable()) {
        if (id)
            m_callbacks[id] = callback;
        else
            callback.call({QJSValue()});
    }
    return id;
}
void CefQuickView::runJavaScript(const QString &source, QJSValue callback) {
    devTools("Runtime.evaluate", {{"expression", source}, {"returnByValue", true}}, callback);
}
void CefQuickView::executeNotificationEvent(const QString &id, const QString &event) {
    auto quoted = [](const QString &value) {
        return QString::fromUtf8(QJsonDocument(QJsonArray{value}).toJson(QJsonDocument::Compact))
            .mid(1)
            .chopped(1);
    };
    runJavaScript("(()=>{const n=window.__resketchNotifications?.get(" + quoted(id) +
                  ");if(n){const e=new Event(" + quoted(event) +
                  ");n.dispatchEvent(e);n['on'+e.type]?.(e);if(e.type==='close')window.__"
                  "resketchNotifications.delete(" +
                  quoted(id) + ")}})()");
}
void CefQuickView::setLifecycleState(LifecycleState value) {
    const bool changed = m_lifecycle != value;
    m_lifecycle = value;
    if (value == LifecycleState::Discarded) {
        m_observer = nullptr;
        m_callbacks.clear();
        m_protocolCallbacks.clear();
        m_pendingAddress.clear();
        m_loading = false;
        emit stateChanged();
        auto browser = m_browser;
        m_browser = nullptr;
        m_pid = 0;
        if (browser)
            browser->GetHost()->CloseBrowser(true);
        m_creating = false;
        {
            QMutexLocker lock(&m_frameMutex);
            m_texture.reset();
            m_popupTexture.reset();
            m_image = {};
            m_popupImage = {};
        }
        update();
        emit renderProcessPidChanged();
    } else {
        ensureBrowser();
        if (m_browser)
            devTools("Page.setWebLifecycleState",
                     {{"state", value == LifecycleState::Frozen ? "frozen" : "active"}});
        syncVisibility();
    }
    if (changed)
        emit lifecycleStateChanged();
}
void CefQuickView::syncVisibility() {
    if (m_browser)
        m_browser->GetHost()->WasHidden(m_lifecycle != LifecycleState::Active || !isVisible());
}
void CefQuickView::syncScreen() {
    if (!m_browser)
        return;
    auto *screen = window() ? window()->screen() : QGuiApplication::primaryScreen();
    m_browser->GetHost()->SetWindowlessFrameRate(screen ? qBound(1, qRound(screen->refreshRate()), 240) : 60);
    m_browser->GetHost()->NotifyScreenInfoChanged();
    m_browser->GetHost()->WasResized();
}
void CefQuickView::reload() {
    if (m_lifecycle == LifecycleState::Discarded)
        setLifecycleState(LifecycleState::Active);
    if (m_browser)
        m_browser->Reload();
    else
        ensureBrowser();
}
void CefQuickView::triggerWebAction(WebAction action) {
    if (action == Reload)
        reload();
}
void CefQuickView::stop() {
    if (m_browser)
        m_browser->StopLoad();
}
void CefQuickView::goBack() {
    if (m_browser)
        m_browser->GoBack();
}
void CefQuickView::goForward() {
    if (m_browser)
        m_browser->GoForward();
}
void CefQuickView::loadHtml(const QString &html, const QUrl &base) {
    m_url = base;
    m_htmlAddress = "data:text/html;base64," + QString::fromLatin1(html.toUtf8().toBase64());
    emit urlChanged();
    m_loading = true;
    emit stateChanged();
    if (!m_browser) {
        const bool creating = m_creating;
        const QUrl previous = m_url;
        m_url = QUrl(m_htmlAddress);
        ensureBrowser();
        m_url = previous;
        if (creating)
            m_pendingAddress = m_htmlAddress;
    } else
        m_browser->GetMainFrame()->LoadURL(utf8(m_htmlAddress));
}
void CefQuickView::acceptAsNewWindow(CefNewWindowRequest *request) {
    if (request)
        request->target = this;
}
void CefQuickView::publishFrame(const QImage &image, bool popup) {
    {
        QMutexLocker lock(&m_frameMutex);
        if (popup) {
            m_popupImage = image;
            m_popupTexture.reset();
        } else {
            m_image = image;
            m_texture.reset();
        }
    }
    if (m_backend != "Bitmap transfer") {
        m_backend = "Bitmap transfer";
        emit renderingBackendChanged();
    }
    update();
}
void CefQuickView::publishAccelerated(const CefAcceleratedPaintInfo &info, bool popup) {
    auto frame = copyCefTexture(info);
    if (!frame) {
        // Recreate the browser with bitmap transport only if importing shared
        // GPU buffers fails. Never continue displaying an empty texture.
        if (m_backend != "Shared texture unavailable") {
            m_backend = "Shared texture unavailable";
            emit renderingBackendChanged();
            qWarning("CEF: DMA-BUF import failed; switching this view to bitmap transport");
            QTimer::singleShot(0, this, [this] {
                qputenv("RESKETCH_CEF_BITMAP", "1");
                const auto current = m_lifecycle;
                setLifecycleState(LifecycleState::Discarded);
                setLifecycleState(current);
            });
        }
        return;
    }
    {
        QMutexLocker lock(&m_frameMutex);
        if (popup) {
            m_popupTexture = std::move(frame);
            m_popupImage = {};
        } else {
            m_texture = std::move(frame);
            m_image = {};
        }
    }
    if (m_backend != "GPU shared texture") {
        m_backend = "GPU shared texture";
        emit renderingBackendChanged();
    }
    update();
}
QSGNode *CefQuickView::updatePaintNode(QSGNode *old, UpdatePaintNodeData *) {
    auto *node = static_cast<ViewNode *>(old);
    if (!node)
        node = new ViewNode;
    QMutexLocker lock(&m_frameMutex);
    node->background.setRect(boundingRect());
    node->background.setColor(m_background);
    setTexture(window(), node, node->page, node->pageFrame, node->pageImage, m_texture, m_image);
    if (node->page)
        node->page->setRect(boundingRect());
    setTexture(window(), node, node->popup, node->popupFrame, node->popupImage, m_popupTexture, m_popupImage);
    if (node->popup)
        node->popup->setRect(m_popupVisible ? QRectF(m_popupRect) : QRectF());
    return node;
}
void CefQuickView::geometryChange(const QRectF &now, const QRectF &before) {
    QQuickItem::geometryChange(now, before);
    if (m_browser && now.size() != before.size())
        m_browser->GetHost()->WasResized();
}
void CefQuickView::itemChange(ItemChange change, const ItemChangeData &data) {
    QQuickItem::itemChange(change, data);
    if (change == ItemVisibleHasChanged)
        syncVisibility();
}
void CefQuickView::mousePressEvent(QMouseEvent *event) {
    forceActiveFocus(Qt::MouseFocusReason);
    if (m_browser)
        m_browser->GetHost()->SendMouseClickEvent(
            mouse(event->position(), event->modifiers(), event->buttons()), button(event->button()), false,
            1);
    event->accept();
}
void CefQuickView::mouseReleaseEvent(QMouseEvent *event) {
    if (m_browser)
        m_browser->GetHost()->SendMouseClickEvent(
            mouse(event->position(), event->modifiers(), event->buttons()), button(event->button()), true, 1);
    event->accept();
}
void CefQuickView::mouseDoubleClickEvent(QMouseEvent *event) {
    if (m_browser)
        m_browser->GetHost()->SendMouseClickEvent(
            mouse(event->position(), event->modifiers(), event->buttons()), button(event->button()), false,
            2);
    event->accept();
}
void CefQuickView::mouseMoveEvent(QMouseEvent *event) {
    if (m_browser)
        m_browser->GetHost()->SendMouseMoveEvent(
            mouse(event->position(), event->modifiers(), event->buttons()), false);
    event->accept();
}
void CefQuickView::hoverMoveEvent(QHoverEvent *event) {
    if (m_browser)
        m_browser->GetHost()->SendMouseMoveEvent(mouse(event->position(), event->modifiers()), false);
    event->accept();
}
void CefQuickView::hoverLeaveEvent(QHoverEvent *event) {
    if (m_browser)
        m_browser->GetHost()->SendMouseMoveEvent(mouse(event->position(), event->modifiers()), true);
    event->accept();
}
void CefQuickView::wheelEvent(QWheelEvent *event) {
    if (m_browser) {
        auto value = mouse(event->position(), event->modifiers(), event->buttons());
        QPoint delta = event->pixelDelta();
        if (!delta.isNull())
            value.modifiers |= EVENTFLAG_PRECISION_SCROLLING_DELTA;
        else
            delta = event->angleDelta() / 3;
        m_browser->GetHost()->SendMouseWheelEvent(value, delta.x(), delta.y());
    }
    event->accept();
}
void CefQuickView::sendKey(QKeyEvent *event, bool release) {
    if (!m_browser)
        return;
    CefKeyEvent key;
    key.type = release ? KEYEVENT_KEYUP : KEYEVENT_RAWKEYDOWN;
    key.modifiers = modifiers(event->modifiers());
    if (event->isAutoRepeat())
        key.modifiers |= EVENTFLAG_IS_REPEAT;
    key.windows_key_code = keyCode(event->key());
    key.native_key_code = event->nativeScanCode();
    key.is_system_key = event->modifiers().testFlag(Qt::AltModifier);
    if (!event->text().isEmpty())
        key.character = key.unmodified_character = event->text().front().unicode();
    m_browser->GetHost()->SendKeyEvent(key);
    if (!release && !event->modifiers().testFlag(Qt::ControlModifier) &&
        !event->modifiers().testFlag(Qt::MetaModifier))
        for (const auto character : event->text()) {
            key.type = KEYEVENT_CHAR;
            key.character = character.unicode();
            key.windows_key_code = character.unicode();
            m_browser->GetHost()->SendKeyEvent(key);
        }
}
void CefQuickView::keyPressEvent(QKeyEvent *event) {
    sendKey(event, false);
    event->accept();
}
void CefQuickView::keyReleaseEvent(QKeyEvent *event) {
    sendKey(event, true);
    event->accept();
}
void CefQuickView::focusInEvent(QFocusEvent *event) {
    QQuickItem::focusInEvent(event);
    if (m_browser)
        m_browser->GetHost()->SetFocus(true);
}
void CefQuickView::focusOutEvent(QFocusEvent *event) {
    QQuickItem::focusOutEvent(event);
    if (m_browser)
        m_browser->GetHost()->SetFocus(false);
}
QVariant CefQuickView::inputMethodQuery(Qt::InputMethodQuery query) const {
    if (query == Qt::ImEnabled)
        return true;
    if (query == Qt::ImCursorRectangle)
        return m_imeRect;
    return QQuickItem::inputMethodQuery(query);
}
void CefQuickView::inputMethodEvent(QInputMethodEvent *event) {
    if (!m_browser)
        return;
    auto *host = m_browser->GetHost().get();
    if (!event->commitString().isEmpty())
        host->ImeCommitText(utf8(event->commitString()), CefRange(UINT32_MAX, UINT32_MAX), 0);
    if (event->preeditString().isEmpty())
        host->ImeCancelComposition();
    else {
        const int length = event->preeditString().size();
        CefCompositionUnderline line;
        line.range = CefRange(0, length);
        line.color = CefColorSetARGB(255, 0, 0, 0);
        line.thick = false;
        host->ImeSetComposition(utf8(event->preeditString()), {line}, CefRange(UINT32_MAX, UINT32_MAX),
                                CefRange(length, length));
    }
    event->accept();
}
