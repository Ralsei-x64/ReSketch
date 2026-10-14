// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefApp.h"
#include "CefView.h"
#include <QApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItemGrabResult>
#include <QQuickWindow>
#include <QStyleHints>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QThread>
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
        view->loadHtml("<title>CEF "
                       "fixture</"
                       "title><style>html,body{margin:0;background:#e02030}input{position:absolute;top:20px;"
                       "left:20px}#blue{position:absolute;top:150px;width:100%;height:150px;background:#"
                       "2040e0}#long{height:1200px}</style><input id='input'><div id='blue'></div><div "
                       "id='long'></"
                       "div><script>window.seenCreation=window.created;window.ticks=0;setInterval(()=>ticks++"
                       ",20)</script>");
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
        view->setRenderScale(0.5);
        until([&] { return js("devicePixelRatio").toDouble() == 0.5; }, "preview render scale");
        require(js("innerWidth===400 && innerHeight===300").toBool(), "preview keeps the CSS viewport");
        require(view->browser()->GetHost()->GetWindowlessFrameRate() == 30, "overview frame rate budget");
        auto previewCapture = view->grabToImage();
        bool previewCaptured = false;
        QObject::connect(previewCapture.get(), &QQuickItemGrabResult::ready, [&] { previewCaptured = true; });
        until([&] { return previewCaptured; }, "scaled preview capture");
        const auto previewImage = previewCapture->image();
        require(previewImage.pixelColor(100, 100).red() > 180 && previewImage.pixelColor(100, 220).blue() > 180,
                "scaled preview pixels and orientation");
        previewCapture.reset();
        view->setOverviewPreview(false);
        view->setRenderScale(1);
        until([&] { return js("devicePixelRatio").toDouble() == 1; }, "interactive render scale restored");
        QMouseEvent press(QEvent::MouseButtonPress, QPointF(40, 35), QPointF(40, 35), Qt::LeftButton,
                          Qt::LeftButton, Qt::NoModifier);
        QMouseEvent release(QEvent::MouseButtonRelease, QPointF(40, 35), QPointF(40, 35), Qt::LeftButton,
                            Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(view, &press);
        QCoreApplication::sendEvent(view, &release);
        QKeyEvent key(QEvent::KeyPress, Qt::Key_A, Qt::NoModifier, "a");
        QCoreApplication::sendEvent(view, &key);
        until([&] { return js("document.getElementById('input').value").toString() == "a"; },
              "mouse focus and keyboard input");
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
