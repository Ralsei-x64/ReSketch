// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefApp.h"
#include "CefView.h"
#include "include/cef_client.h"
#include "include/cef_dialog_handler.h"
#include <QApplication>
#include <QElapsedTimer>
#include <QEnterEvent>
#include <QFile>
#include <QFileDialog>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItemGrabResult>
#include <QQuickWindow>
#include <QStyleHints>
#include <QTcpSocket>
#include <QTcpServer>
#include <QTemporaryDir>
#include <QThread>
#include <QTimer>
#include <QUrlQuery>
#include <QWheelEvent>
#include <cstdio>
#include <cstdlib>

static void require(bool ok, const char *message) {
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", message);
        std::exit(1);
    }
}
template <class F> void until(F predicate, const char *message, int timeout = 15000) {
    QElapsedTimer elapsed;
    elapsed.start();
    while (!predicate() && elapsed.elapsed() < timeout) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
        QThread::msleep(1);
    }
    require(predicate(), message);
}
class CancelledPicker final : public CefFileDialogCallback {
  public:
    bool cancelled = false;
    void Cancel() override { cancelled = true; }
    void Continue(const std::vector<CefString> &) override {
        require(false, "Cancelled picker must not return any files");
    }
  private:
    IMPLEMENT_REFCOUNTING(CancelledPicker);
};
int main(int argc, char **argv) {
    qputenv("QT_NO_GLIB", "1");
    const bool gpu = argc > 1 && QByteArray(argv[1]) == "--gpu";
    if (!gpu) {
        qputenv("QT_QUICK_BACKEND", "software");
        qputenv("RESKETCH_CEF_FLAGS", "--disable-gpu --no-sandbox");
    } else {
        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
        qputenv("QT_XCB_GL_INTEGRATION", "xcb_egl");
    }
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QCoreApplication::setAttribute(Qt::AA_DontUseNativeDialogs);
    QApplication app(argc, argv);
    QTemporaryDir directory;
    require(directory.isValid(), "temporary profile");
    qputenv("RESKETCH_CEF_CACHE_ROOT", directory.path().toUtf8());
    {
        QQmlEngine engine;
        engine.addImportPath(RESKETCH_TEST_IMPORTS);
        QQmlComponent component(&engine);
        component.setData(R"QML(
import QtQuick
import ReSketch.Cef
CefView {
    width:400; height:300
    profile: CefProfile { offTheRecord:true }
    property var result
    property bool answered:false
    function evaluate(source) {answered=false;runJavaScript(source, function(value){result=value;answered=true})}
    userScripts.collection: [{sourceCode:'window.created=true', injectionPoint:CefScript.DocumentCreation},
                            {sourceCode:'window.ready=true', injectionPoint:CefScript.DocumentReady}]
}
)QML",
                          QUrl());
        std::unique_ptr<QObject> object(component.create());
        if (!object)
            qWarning() << component.errors();
        require(bool(object), "QML CefView creation");
        auto *view = qobject_cast<CefQuickView *>(object.get());
        QQuickWindow window;
        window.resize(400, 300);
        view->setParentItem(window.contentItem());
        window.show();
        fprintf(stderr, "Loading local fixture\n");
        const QString fixtureHtml = "<title>CEF "
                       "fixture</"
                       "title><style>html,body{margin:0;background:#e02030}input{position:absolute;top:20px;"
                       "left:20px}#blue{position:absolute;top:150px;width:100%;height:150px;background:#"
                       "2040e0}#long{height:1200px}</style><input id='input'><div id='blue'></div><div "
                       "id='long'></"
                       "div><script>window.seenCreation=window.created;window.ticks=0;setInterval(()=>ticks++"
                       ",20)</script>";
        QTcpServer fixtureServer;
        require(fixtureServer.listen(QHostAddress::LocalHost), "Clipboard/font fixture HTTP server");
        QObject::connect(&fixtureServer, &QTcpServer::newConnection, &fixtureServer, [&] {
            auto *socket = fixtureServer.nextPendingConnection();
            QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            QObject::connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                const auto headers = socket->property("headers").toByteArray() + socket->readAll();
                socket->setProperty("headers", headers);
                if (!headers.contains("\r\n\r\n")) return;
                const auto body = fixtureHtml.toUtf8();
                socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\nContent-Length: "
                              + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                socket->disconnectFromHost();
            });
        });
        QObject::connect(view, &CefQuickView::permissionRequested, [&](CefPermission *permission) {
            if (permission->origin().host() == "127.0.0.1") permission->grant();
        });
        const QUrl fixtureUrl(QString("http://127.0.0.1:%1/").arg(fixtureServer.serverPort()));
        view->setUrl(fixtureUrl);
        until(
            [&] {
                return view->title() == "CEF fixture" && !view->loading() && view->renderProcessPid() > 0;
            },
            "page load and renderer PID");
        const auto js = [&](QString expression) {
            QMetaObject::invokeMethod(view, "evaluate", Q_ARG(QVariant, expression));
            until([&] { return view->property("answered").toBool(); }, "JavaScript response");
            return view->property("result");
        };
        require(js("Boolean(seenCreation && ready)").toBool(), "script injection ordering");
        require(js("document.title").toString() == "CEF fixture", "JavaScript result");
        for (const auto setting : {CEF_CONTENT_SETTING_TYPE_CLIPBOARD_READ_WRITE,
                CEF_CONTENT_SETTING_TYPE_LOCAL_FONTS, CEF_CONTENT_SETTING_TYPE_LOOPBACK_NETWORK}) {
            require(view->profile()->context()->GetContentSetting(fixtureUrl.toString().toStdString(),
                    fixtureUrl.toString().toStdString(), setting) == CEF_CONTENT_SETTING_VALUE_ALLOW,
                    "Accepted origins receive clipboard/font/loopback permissions before script requests");
            require(view->profile()->context()->GetContentSetting("https://example.invalid", "https://example.invalid",
                    setting) != CEF_CONTENT_SETTING_VALUE_ALLOW, "Other origins do not inherit permissions");
        }
        js("window.fontCount=-1;queryLocalFonts().then(fonts=>fontCount=fonts.length,e=>window.fontError=e.name)");
        until([&] { return js("fontCount>=0 || Boolean(window.fontError)").toBool(); }, "Local-font enumeration completes");
        require(js("fontCount>0").toBool(), "CEF exposes installed local fonts to an accepted origin");
        js("window.pastes=0;addEventListener('paste',e=>{e.preventDefault();window.pastes++;window.pasteTypes=[...e.clipboardData.types]});document.querySelector('input').focus()");
        fprintf(stderr, "Reading clipboard through native paste\n");
        view->browser()->GetMainFrame()->Paste();
        until([&] { return js("pastes").toInt() == 1; }, "Native paste delivers an event without stalling the renderer");
        fprintf(stderr, "Native clipboard event returned\n");
        QKeyEvent pasteDown(QEvent::KeyPress, Qt::Key_V, Qt::ControlModifier, "\x16");
        QKeyEvent pasteUp(QEvent::KeyRelease, Qt::Key_V, Qt::ControlModifier);
        QCoreApplication::sendEvent(view, &pasteDown);
        QCoreApplication::sendEvent(view, &pasteUp);
        until([&] { return js("pastes").toInt() == 2; }, "Ctrl+V delivers paste without stalling the renderer");
        struct PickerFilters {
            std::vector<CefString> accepted, expanded;
            QStringList expected;
        };
        for (const auto &filters : {
            PickerFilters{{".fig", "image/*"}, {"", ".png;.jpg;.jpeg;.webp;.svg;.avif;.heic;.heif"},
                          {"*.fig", "*.png", "*.jpeg", "*.webp", "*.svg", "*.avif", "*.heic", "*.heif"}},
            PickerFilters{{".fig", "image/*"}, {}, {"*.fig", "*.png", "*.jpg", "*.webp", "*.svg"}},
            PickerFilters{{"image/jpeg", "image/x-unknown", ".fig"}, {}, {"*.jpg", "*.jpeg", "*.fig"}}
        }) {
            QTimer::singleShot(0, &app, [&] {
                auto *dialog = qobject_cast<QFileDialog *>(QApplication::activeModalWidget());
                require(dialog, "Qt file picker opened");
                const auto names = dialog->nameFilters();
                require(names.size() == 2 && names.last() == "All files (*)", "File picker offers an unfiltered fallback");
                for (const auto &pattern : filters.expected)
                    require(names.first().contains(pattern), "File picker includes accepted image extensions");
                dialog->reject();
            });
            CefRefPtr<CancelledPicker> result = new CancelledPicker;
            require(view->browser()->GetHost()->GetClient()->GetDialogHandler()->OnFileDialog(
                view->browser(), FILE_DIALOG_OPEN_MULTIPLE, "Import fixture", directory.path().toStdString(),
                filters.accepted, filters.expanded, {}, result), "Custom picker handles the request");
            require(result->cancelled, "Picker cancellation discards the selection");
        }
        view->setProperty("dedicatedHome", true);
        int fileOpens = 0, homeLoads = 0;
        auto navigation =
            QObject::connect(view, &CefQuickView::navigationRequested, [&](CefNavigationRequest *request) {
                if (request->url.host() == "www.figma.com" && request->url.path().startsWith("/design/")) {
                    ++fileOpens;
                    request->reject();
                }
            });
        auto loads = QObject::connect(view, &CefQuickView::loadStateChanged, [&](QVariantMap info) {
            if (info.value("status").toInt() == CefQuickView::LoadStartedStatus)
                ++homeLoads;
        });
        js("for(let "
           "i=0;i<20;i++)__resketchNative('home-file','https://www.figma.com/design/Burst_'+i+'/File')");
        until([&] { return fileOpens == 20; }, "Home file-open burst delivered");
        require(homeLoads == 0 && js("seenCreation").toBool(), "Home document survives file-open bursts");
        auto redirect = QObject::connect(view, &CefQuickView::urlChanged, [&] {
            if (view->url().host() == "www.figma.com")
                view->restoreHistoryUrl(QUrl("about:blank"));
        });
        view->setUrl(QUrl("https://www.figma.com/design/Reentrant/File"));
        require(js("seenCreation").toBool() && homeLoads == 0,
                "URL handler restoration does not reload Home");
        QObject::disconnect(redirect);
        QObject::disconnect(navigation);
        QObject::disconnect(loads);
        view->setProperty("dedicatedHome", false);
        until([&] { return view->renderingBackend() != "Waiting for frame"; }, "rendered frame");
        auto capture = view->grabToImage();
        bool captured = false;
        QObject::connect(capture.get(), &QQuickItemGrabResult::ready, [&] { captured = true; });
        until([&] { return captured; }, "frame capture");
        const auto image = capture->image();
        const auto top = image.pixelColor(100, 100), bottom = image.pixelColor(100, 220);
        fprintf(stderr, "Frame pixels: %s %s\n", qPrintable(top.name()), qPrintable(bottom.name()));
        image.save(gpu ? "/tmp/resketch-cef-gpu-frame.png" : "/tmp/resketch-cef-software-frame.png");
        require(top.red() > 180 && top.blue() < 90 && bottom.blue() > 180 && bottom.red() < 90,
                "frame colors and orientation");
        capture.reset();
        view->setOverviewPreview(true);
        require(js("devicePixelRatio").toDouble() == 1, "preview keeps native pixel density");
        require(js("innerWidth===400 && innerHeight===300").toBool(), "preview keeps the CSS viewport");
        require(view->browser()->GetHost()->GetWindowlessFrameRate() == 30, "overview frame rate budget");
        auto previewCapture = view->grabToImage();
        bool previewCaptured = false;
        QObject::connect(previewCapture.get(), &QQuickItemGrabResult::ready, [&] { previewCaptured = true; });
        until([&] { return previewCaptured; }, "preview capture");
        const auto previewImage = previewCapture->image();
        require(previewImage.pixelColor(100, 100).red() > 180 && previewImage.pixelColor(100, 220).blue() > 180,
                "preview pixels and orientation");
        previewCapture.reset();
        view->setOverviewPreview(false);
        require(js("devicePixelRatio").toDouble() == 1, "interactive pixel density stays unchanged");
        const QPointF pointerPosition(200, 100);
        QEnterEvent enter(pointerPosition, pointerPosition, window.mapToGlobal(pointerPosition));
        QCoreApplication::sendEvent(&window, &enter);
        const auto movePointer = [&] {
            QMouseEvent motion(QEvent::MouseMove, pointerPosition, window.mapToGlobal(pointerPosition),
                               Qt::NoButton, Qt::NoButton, Qt::NoModifier);
            QCoreApplication::sendEvent(&window, &motion);
        };
        js("document.body.style.cursor=\"url('data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2216%22%20height%3D%2216%22%3E%3Crect%20width%3D%2216%22%20height%3D%2216%22%20fill%3D%22%23ff0000%22%2F%3E%3C%2Fsvg%3E') 3 5, auto\"");
        movePointer();
        until([&] { return view->cursor().shape() == Qt::BitmapCursor; }, "custom web cursor");
        require(window.cursor().shape() == Qt::BitmapCursor, "custom web cursor reaches the native window");
        QQuickItem chrome(window.contentItem());
        chrome.setX(300); chrome.setWidth(100); chrome.setHeight(300); chrome.setZ(1);
        chrome.setCursor(QCursor(Qt::IBeamCursor));
        QMouseEvent leaveCanvas(QEvent::MouseMove, QPointF(350, 100), window.mapToGlobal(QPointF(350, 100)),
                                Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(&window, &leaveCanvas);
        until([&] { return window.cursor().shape() == Qt::IBeamCursor; }, "native control cursor after leaving web view");
        movePointer();
        until([&] { return window.cursor().shape() == Qt::BitmapCursor; }, "web cursor after returning to canvas");
        require(!view->useSystemCursor(), "Figma custom cursors enabled by default");
        require(view->cursor().hotSpot() == QPoint(3, 5), "custom cursor hotspot");
        require(view->cursor().pixmap().toImage().pixelColor(8, 8) == QColor(Qt::red), "custom cursor BGRA pixels");
        view->setUseSystemCursor(true);
        require(view->cursor().shape() == Qt::ArrowCursor, "system cursor toggle applies immediately");
        view->setUseSystemCursor(false);
        require(view->cursor().shape() == Qt::BitmapCursor, "custom cursor is restored without reloading");
        js("document.body.style.cursor='none'");
        movePointer();
        until([&] { return view->cursor().shape() == Qt::BlankCursor; }, "hidden web cursor");
        view->setUseSystemCursor(true);
        require(view->cursor().shape() == Qt::ArrowCursor, "system preference supplies a visible cursor");
        view->setUseSystemCursor(false);
        js("document.body.style.cursor='auto'");
        movePointer();
        until([&] { return view->cursor().shape() == Qt::ArrowCursor; }, "standard cursor restored");
        QMouseEvent press(QEvent::MouseButtonPress, QPointF(40, 35), QPointF(40, 35), Qt::LeftButton,
                          Qt::LeftButton, Qt::NoModifier);
        QMouseEvent release(QEvent::MouseButtonRelease, QPointF(40, 35), QPointF(40, 35), Qt::LeftButton,
                            Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(view, &press);
        QCoreApplication::sendEvent(view, &release);
        js("window.pressedKeys=[];document.getElementById('input').addEventListener('keypress',e=>pressedKeys.push(e.key))");
        QKeyEvent key(QEvent::KeyPress, Qt::Key_A, Qt::NoModifier, "a");
        QCoreApplication::sendEvent(view, &key);
        until([&] { return js("document.getElementById('input').value").toString() == "a"; },
              "mouse focus and keyboard input");
        for (const auto entry : {std::pair{Qt::Key_E, 26}, std::pair{Qt::Key_N, 57}}) {
            const QString text(QChar(ushort(entry.first)).toLower());
            QKeyEvent typed(QEvent::KeyPress, entry.first, Qt::NoModifier, entry.second, 0, 0, text);
            QCoreApplication::sendEvent(view, &typed);
        }
        until([&] { return js("document.getElementById('input').value").toString() == "aen"; },
              "comment shortcut letters type into editable fields");
        require(js("pressedKeys.join('')").toString() == "aen",
                "keypress keys match typed letters instead of numeric keypad/function keys");
        js("document.getElementById('input').value='';window.downKeys=[];document.getElementById('input').addEventListener('keydown',e=>downKeys.push(e.key))");
        const QString symbols = QStringLiteral("!@#$%^&*()");
        for (int index = 0; index < symbols.size(); ++index) {
            const auto symbol = symbols[index];
            QKeyEvent typed(QEvent::KeyPress, symbol.unicode(), Qt::ShiftModifier, 10 + index, 0, 0,
                            QString(symbol));
            QCoreApplication::sendEvent(view, &typed);
        }
        until([&] { return js("document.getElementById('input').value").toString() == symbols; },
              "shifted number-row symbols insert into text fields");
        require(js("downKeys.join('')").toString() == symbols, "shifted symbols have correct DOM key names");
        QWheelEvent wheel(QPointF(200, 200), QPointF(200, 200), QPoint(0, -100), QPoint(), Qt::NoButton,
                          Qt::NoModifier, Qt::ScrollUpdate, false);
        QCoreApplication::sendEvent(view, &wheel);
        until([&] { return js("scrollY").toInt() > 0; }, "trackpad pixel scrolling");
        QElapsedTimer gestureEnd;
        gestureEnd.start();
        while (gestureEnd.elapsed() < 350) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
            QThread::msleep(1);
        }
        js("scrollTo(0,0);window.scrollSamples=[];addEventListener('scroll',()=>scrollSamples.push(scrollY)"
           ")");
        until([&] { return js("scrollY").toInt() == 0; }, "reset scroll position");
        QWheelEvent mouseWheel(QPointF(200, 200), QPointF(200, 200), QPoint(), QPoint(0, -120), Qt::NoButton,
                               Qt::NoModifier, Qt::NoScrollPhase, false);
        QCoreApplication::sendEvent(view, &mouseWheel);
        const int wheelDistance = 40 * QGuiApplication::styleHints()->wheelScrollLines();
        until([&] { return js("scrollY").toInt() >= wheelDistance; }, "mouse wheel scrolling");
        const auto samples =
            js(QString("scrollSamples.filter(y=>y>0 && y<%1).length").arg(wheelDistance)).toInt();
        fprintf(stderr, "Wheel animation intermediate samples: %d\n", samples);
        require(samples >= 2, "Chromium mouse wheel scrolling animates through intermediate positions");
        std::unique_ptr<QObject> popupObject(component.create());
        auto *popup = qobject_cast<CefQuickView *>(popupObject.get());
        popup->setParentItem(window.contentItem());
        popup->setVisible(false);
        int popupRequests = 0;
        QObject::connect(view, &CefQuickView::newWindowRequested, [&](CefNewWindowRequest *request) {
            ++popupRequests;
            if (request->requestedUrl == QUrl("about:blank"))
                popup->acceptAsNewWindow(request);
        });
        js("window.child=window.open('about:blank');child.document.title='Popup fixture'");
        until([&] { return popup->title() == "Popup fixture"; }, "popup adoption");
        require(js("child.opener===window").toBool(), "popup opener preserved");
        auto requestPopup = CefDictionaryValue::Create();
        requestPopup->SetString("expression", "window.open('https://example.invalid/')");
        requestPopup->SetBool("userGesture", true);
        view->browser()->GetHost()->ExecuteDevToolsMethod(100000, "Runtime.evaluate", requestPopup);
        until([&] { return popupRequests == 2; }, "popup policy callback");
        popup->setParentItem(nullptr);
        popupObject.reset();
        bool downloaded = false;
        auto acceptDownload =
            QObject::connect(view->profile(), &CefProfile::downloadRequested, [&](CefDownload *download) {
                download->downloadDirectory = directory.path();
                download->downloadFileName = "export.txt";
                download->accept();
            });
        QObject::connect(view->profile(), &CefProfile::downloadFinished, [&](CefDownload *download) {
            downloaded = download->state == CefDownload::DownloadCompleted;
        });
        js("(()=>{const a=document.createElement('a');a.href=URL.createObjectURL(new Blob(['CEF "
           "export']));a.download='export.txt';a.click()})()");
        until([&] { return downloaded; }, "download completion");
        QFile file(directory.filePath("export.txt"));
        require(file.open(QIODevice::ReadOnly) && file.readAll() == "CEF export", "download contents");
        QObject::disconnect(acceptDownload);
        bool cancelled = false;
        auto cancelDownload = QObject::connect(view->profile(), &CefProfile::downloadRequested,
                                               [&](CefDownload *download) { download->cancel(); });
        auto cancellation =
            QObject::connect(view->profile(), &CefProfile::downloadFinished, [&](CefDownload *download) {
                cancelled = download->state == CefDownload::DownloadCancelled;
            });
        view->browser()->GetHost()->StartDownload(
            js("URL.createObjectURL(new Blob(['discard me']))").toString().toStdString());
        until([&] { return cancelled; }, "cancelled export reaches Chromium's terminal state");
        require(view->profile()->downloads.isEmpty() && !QFile::exists(directory.filePath("cancelled.txt")),
                "cancelled export is discarded");
        QObject::disconnect(cancelDownload);
        QObject::disconnect(cancellation);
        std::unique_ptr<QObject> toolsObject(component.create());
        auto *tools = qobject_cast<CefQuickView *>(toolsObject.get());
        tools->setParentItem(window.contentItem());
        tools->setInspectedView(view);
        until([&] { return tools->browser() && !tools->title().isEmpty(); }, "embedded Developer Tools");
        const QUrl endpoint("ws://" + QUrlQuery(tools->url()).queryItemValue("ws"));
        QTcpSocket socket;
        socket.connectToHost(endpoint.host(), endpoint.port());
        until([&] { return socket.state() == QAbstractSocket::ConnectedState; },
              "DevTools endpoint connection");
        const QByteArray handshake =
            "GET " + endpoint.path().toUtf8() + " HTTP/1.1\r\nHost: " + endpoint.authority().toUtf8() +
            "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: "
            "dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nOrigin: devtools://devtools\r\n\r\n";
        socket.write(handshake);
        QByteArray response;
        until(
            [&] {
                response += socket.readAll();
                return response.contains("\r\n\r\n");
            },
            "DevTools WebSocket response");
        require(response.startsWith("HTTP/1.1 101"), "internal DevTools origin is accepted");
        socket.abort();
        tools->setInspectedView(nullptr);
        tools->setParentItem(nullptr);
        toolsObject.reset();
        fprintf(stderr, "PASS: pixels, input, trackpad, popups, downloads and Developer Tools\n");
        fprintf(stderr, "PASS: load, scripts, JavaScript and %s\n", qPrintable(view->renderingBackend()));
        const auto first = js("ticks").toInt();
        until([&] { return js("ticks").toInt() > first; }, "active timers");
        view->setLifecycleState(CefQuickView::LifecycleState::Frozen);
        QThread::msleep(50);
        QCoreApplication::processEvents();
        const auto frozen = js("ticks").toInt();
        QElapsedTimer elapsed;
        elapsed.start();
        while (elapsed.elapsed() < 200) {
            QCoreApplication::processEvents();
            QThread::msleep(1);
        }
        require(js("ticks").toInt() == frozen, "frozen timers");
        view->setLifecycleState(CefQuickView::LifecycleState::Active);
        until([&] { return js("ticks").toInt() > frozen; }, "resumed timers");
        view->setLifecycleState(CefQuickView::LifecycleState::Discarded);
        require(!view->browser(), "discarded browser released");
        view->setLifecycleState(CefQuickView::LifecycleState::Active);
        view->loadHtml("<title>Restored</title><body>restored</body>");
        until([&] { return view->title() == "Restored" && !view->loading(); }, "reloaded discarded view");
        view->setParentItem(nullptr);
        object.reset();
        window.close();
    }
    ReSketchCef::shutdown();
    fprintf(stderr, "PASS: freeze, resume, discard and shutdown\n");
}
