// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefApp.h"
#include "CefView.h"
#include "include/cef_client.h"
#include "include/cef_dialog_handler.h"
#include <QApplication>
#include <QBuffer>
#include <QClipboard>
#include <QDragEnterEvent>
#include <QElapsedTimer>
#include <QEnterEvent>
#include <QFile>
#include <QFileDialog>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QMimeData>
#include <QProcess>
#include <QPointingDevice>
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
#include <stdexcept>
#include <time.h>

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
static void processFor(int milliseconds) {
    QEventLoop loop;
    QTimer::singleShot(milliseconds, &loop, &QEventLoop::quit);
    loop.exec();
}
class ClipboardInput final : public QObject {
  public:
    bool ready = false;

  protected:
    bool eventFilter(QObject *, QEvent *event) override {
        if (event->type() == QEvent::KeyPress)
            ready = true;
        return false;
    }
};
class LazyClipboard final : public QMimeData {
  public:
    QStringList formats() const override {
        return QMimeData::formats() + QStringList{"application/web;type=\"custom/format0\""};
    }

  protected:
    QVariant retrieveData(const QString &format, QMetaType type) const override {
        if (format == "application/web;type=\"custom/format0\"") {
            puts("binary-read");
            fflush(stdout);
            return QByteArray(16 * 1024 * 1024, 'q');
        }
        return QMimeData::retrieveData(format, type);
    }
};
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
    const auto hasArgument = [&](const char *argument) {
        for (int i = 1; i < argc; ++i) if (QByteArray(argv[i]) == argument) return true;
        return false;
    };
    const bool clipboardOwner = hasArgument("--clipboard-owner");
    const bool clipboardBenchmark = hasArgument("--clipboard");
    const bool gpu = hasArgument("--gpu");
    const bool sandbox = hasArgument("--sandbox");
    if (!gpu) {
        qputenv("QT_QUICK_BACKEND", "software");
        qputenv("RESKETCH_CEF_FLAGS", sandbox ? "--disable-gpu" : "--disable-gpu --no-sandbox");
    } else {
        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
        qputenv("QT_XCB_GL_INTEGRATION", "xcb_egl");
    }
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QCoreApplication::setAttribute(Qt::AA_DontUseNativeDialogs);
    QApplication app(argc, argv);
    if (clipboardOwner) {
        require(argc > 2, "Clipboard owner payload type");
        const QByteArray kind(argv[2]);
        QMimeData *mime = kind == "bridge" ? new LazyClipboard : new QMimeData;
        if (kind == "bridge") {
            mime->setText(QStringLiteral("ReSketch clipboard α\n二"));
            mime->setHtml("<b>ReSketch clipboard</b>");
            mime->setData("application/web;type=\"custom/formatmap\"", "opaque-format-map");
        } else if (kind == "image") {
            QImage image(2048, 2048, QImage::Format_RGB32);
            quint32 noise = 1;
            for (int y = 0; y < image.height(); ++y) {
                auto *line = reinterpret_cast<quint32 *>(image.scanLine(y));
                for (int x = 0; x < image.width(); ++x) {
                    noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5;
                    line[x] = noise | 0xff000000;
                }
            }
            QByteArray png;
            QBuffer buffer(&png);
            buffer.open(QIODevice::WriteOnly);
            require(image.save(&buffer, "PNG"), "Clipboard image encoding");
            mime->setData("image/png", png);
        } else {
            mime->setText(QString(4 * 1024 * 1024, 'x'));
            if (kind == "html") mime->setHtml("<b>" + QString(4 * 1024 * 1024, 'y') + "</b>");
        }
        QQuickWindow nativeWindow;
        ClipboardInput nativeInput;
        if (kind == "native") {
            app.installEventFilter(&nativeInput);
            nativeWindow.setTitle("ReSketch external clipboard source");
            nativeWindow.resize(240, 120);
            nativeWindow.show();
            nativeWindow.requestActivate();
            until([&] { return nativeInput.ready && QGuiApplication::focusWindow() == &nativeWindow; },
                  "External Wayland source has input focus");
            mime->setText(QStringLiteral("External Wayland α\n二"));
            mime->setHtml("<b>External Wayland</b>");
        }
        app.clipboard()->setMimeData(mime);
        if (kind == "native") {
            processFor(100);
            nativeWindow.hide();
        }
        puts("ready");
        fflush(stdout);
        return app.exec();
    }
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
    userScripts.collection: [{sourceCode:'window.created=true;window.pointerLockAtCreation=!!Element.prototype.requestPointerLock', injectionPoint:CefScript.DocumentCreation},
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
        require(!js("pointerLockAtCreation || !!document.documentElement.requestPointerLock").toBool(),
                "Unsupported OSR pointer lock is absent before page feature detection");
        require(js("document.title").toString() == "CEF fixture", "JavaScript result");
        // VP9 playback must preserve the canvas context, including after a reload.
        if (gpu) {
            QFile videoFile(QStringLiteral(RESKETCH_TEST_VIDEO));
            require(videoFile.open(QIODevice::ReadOnly), "Local video fixture");
            const QString videoUrl = "data:video/webm;base64," + QString::fromLatin1(videoFile.readAll().toBase64());
            for (int pass = 0; pass < 2; ++pass) {
                js(R"JS(
                    window.videoCheck={frames:0,lost:0,error:'',red:false};
                    window.videoCanvas=document.createElement('canvas');
                    videoCanvas.width=640;videoCanvas.height=480;document.body.appendChild(videoCanvas);
                    videoCanvas.addEventListener('webglcontextlost',e=>{e.preventDefault();videoCheck.lost++});
                    const gl=videoCanvas.getContext('webgl2')||videoCanvas.getContext('webgl');
                    if(!gl){videoCheck.error='WebGL unavailable';}else{
                        const debug=gl.getExtension('WEBGL_debug_renderer_info');
                        videoCheck.renderer=gl.getParameter(debug?debug.UNMASKED_RENDERER_WEBGL:gl.RENDERER);
                        const texture=gl.createTexture(),framebuffer=gl.createFramebuffer();
                        gl.bindTexture(gl.TEXTURE_2D,texture);
                        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);
                        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);
                        window.fixtureVideo=document.createElement('video');
                        fixtureVideo.muted=true;fixtureVideo.loop=true;document.body.appendChild(fixtureVideo);
                        fixtureVideo.onerror=()=>videoCheck.error='Video decode failed';
                        const frame=()=>{
                            if(gl.isContextLost()){videoCheck.lost++;return;}
                            try{
                                gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,fixtureVideo);
                                gl.bindFramebuffer(gl.FRAMEBUFFER,framebuffer);
                                gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,texture,0);
                                const pixel=new Uint8Array(4);gl.readPixels(1,1,1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixel);
                                videoCheck.red=pixel[0]>180&&pixel[1]<90&&pixel[2]<90;
                                if(gl.getError()!==gl.NO_ERROR)videoCheck.error='Video texture upload failed';
                                videoCheck.frames++;
                            }catch(e){videoCheck.error=String(e);}
                            fixtureVideo.requestVideoFrameCallback(frame);
                        };
                        fixtureVideo.requestVideoFrameCallback(frame);
                    }
                )JS");
                require(js("videoCheck.error").toString().isEmpty(), "WebGL is available before video playback");
                js("fixtureVideo.src='" + videoUrl + "';fixtureVideo.play().catch(e=>videoCheck.error=String(e))");
                until([&] { return js("videoCheck.frames>=12||videoCheck.lost>0||!!videoCheck.error").toBool(); },
                      "Video frames reach WebGL");
                fprintf(stderr, "Video WebGL pass %d: %s\n", pass+1, qPrintable(js("JSON.stringify(videoCheck)").toString()));
                require(js("videoCheck.frames>=12 && !videoCheck.lost && !videoCheck.error && videoCheck.red").toBool(),
                        "Video playback preserves WebGL and produces real pixels");
                view->reload();
                until([&] { return !view->loading() && js("typeof videoCheck==='undefined' && ready===true").toBool(); },
                      "Video page reload completes");
            }
            fprintf(stderr, "PASS: video playback, video-to-WebGL uploads and WebGL after reload\n");
            if (hasArgument("--video-only")) {
                view->setParentItem(nullptr);object.reset();window.close();ReSketchCef::shutdown();return 0;
            }
        }
        for (const auto setting : {CEF_CONTENT_SETTING_TYPE_CLIPBOARD_READ_WRITE,
                CEF_CONTENT_SETTING_TYPE_LOCAL_FONTS, CEF_CONTENT_SETTING_TYPE_LOOPBACK_NETWORK}) {
            require(view->profile()->context()->GetContentSetting(fixtureUrl.toString().toStdString(),
                    fixtureUrl.toString().toStdString(), setting) == CEF_CONTENT_SETTING_VALUE_ALLOW,
                    "Accepted origins receive clipboard/font/loopback permissions before script requests");
            require(view->profile()->context()->GetContentSetting("https://example.invalid", "https://example.invalid",
                    setting) != CEF_CONTENT_SETTING_VALUE_ALLOW, "Other origins do not inherit permissions");
        }
        if (hasArgument("--wayland-clipboard")) {
            require(QGuiApplication::platformName().startsWith("wayland"), "Native Wayland clipboard test platform");
            ClipboardInput input;
            app.installEventFilter(&input);
            window.setTitle("ReSketch Wayland clipboard check");
            window.requestActivate();
            until([&] { return QGuiApplication::focusWindow() == &window; },
                  "Wayland clipboard window has keyboard focus");
            fprintf(stderr, "Waiting for a key press in the Wayland test window (input serial required)\n");
            until([&] { return input.ready; }, "Wayland clipboard has a native input serial");
            processFor(200);
            auto *clipboard = app.clipboard();
            auto saved = std::make_unique<QMimeData>();
            const auto *original = clipboard->mimeData();
            for (const auto &format : original->formats())
                saved->setData(format, original->data(format));
            if (original->hasImage())
                saved->setImageData(original->imageData());
            QProcess owner;
            QString failure;
            try {
                const auto check = [](bool ok, const char *message) {
                    if (!ok)
                        throw std::runtime_error(message);
                };
                const auto wait = [&](auto predicate, const char *message) {
                    QElapsedTimer timer;
                    timer.start();
                    while (!predicate() && timer.elapsed() < 10000)
                        processFor(5);
                    check(predicate(), message);
                };
                wait([&] { return QGuiApplication::focusWindow() == &window; }, "Clipboard fixture retains focus");
                input.ready = false;
                wait([&] { return input.ready; }, "Fresh input authorizes native clipboard copy");
                auto *native = new QMimeData;
                native->setText(QStringLiteral("Native Wayland α\n二"));
                native->setHtml("<b>Native Wayland</b>");
                clipboard->setMimeData(native);
                processFor(100);
                js("window.nativePaste=null;document.querySelector('input').focus();addEventListener('paste',e=>{e."
                   "preventDefault();nativePaste={text:e.clipboardData.getData('text/"
                   "plain'),html:e.clipboardData.getData('text/html'),files:e.clipboardData.files.length}})");
                view->browser()->GetMainFrame()->Paste();
                wait([&] { return js("!!nativePaste").toBool(); }, "Native Wayland paste arrives in Chromium");
                check(js("nativePaste.text").toString() == QStringLiteral("Native Wayland α\n二") &&
                          js("nativePaste.html").toString() == "<b>Native Wayland</b>",
                      "Wayland text and HTML survive Chromium paste");
                js("addEventListener('copy',e=>{e.preventDefault();e.clipboardData.setData('text/plain','Chromium "
                   "text');e.clipboardData.setData('text/html','<i>Chromium "
                   "text</i>');e.clipboardData.setData('application/x-resketch','custom bytes')})");
                view->browser()->GetMainFrame()->Copy();
                wait([&] { return clipboard->text() == "Chromium text"; }, "Chromium copy reaches native Wayland");
                check(clipboard->mimeData()->html() == "<i>Chromium text</i>",
                      "Chromium HTML survives native Wayland copy");
                check(clipboard->mimeData()->hasFormat("chromium/x-web-custom-data"),
                      "Chromium custom clipboard map is advertised");
                check(!clipboard->mimeData()->data("chromium/x-web-custom-data").isEmpty(),
                      "Chromium custom clipboard bytes survive Wayland copy");
                auto environment = QProcessEnvironment::systemEnvironment();
                environment.insert("QT_QPA_PLATFORM", "xcb");
                owner.setProcessEnvironment(environment);
                owner.start(app.applicationFilePath(), {"--clipboard-owner", "bridge"});
                check(owner.waitForStarted(), "External X11 clipboard owner starts");
                QByteArray output;
                wait(
                    [&] {
                        output += owner.readAllStandardOutput();
                        return output.contains("ready\n");
                    },
                    "External X11 clipboard is ready");
                wait([&] { return clipboard->mimeData()->hasFormat("application/web;type=\"custom/format0\""); },
                     "Custom formats reach Wayland without reading their bytes");
                processFor(100);
                output += owner.readAllStandardOutput();
                check(!output.contains("binary-read"), "Large Figma-style clipboard data is fetched lazily");
                QElapsedTimer transfer;
                transfer.start();
                const auto bytes = clipboard->mimeData()->data("application/web;type=\"custom/format0\"");
                check(bytes == QByteArray(16 * 1024 * 1024, 'q'),
                      "Large custom clipboard payload survives Wayland transfer");
                fprintf(stderr, "16 MiB custom transfer: %lld ms\n", (long long)transfer.elapsed());
                check(transfer.elapsed() < 3000, "Large custom clipboard transfer does not stall");
                check(clipboard->mimeData()->data("application/web;type=\"custom/formatmap\"") == "opaque-format-map",
                      "Custom clipboard format map is unchanged");
                check(clipboard->text() == QStringLiteral("ReSketch clipboard α\n二"),
                      "X11 source text is decoded as UTF-8");
                owner.terminate();
                owner.waitForFinished(2000);
                environment.insert("QT_QPA_PLATFORM", "wayland");
                owner.setProcessEnvironment(environment);
                owner.start(app.applicationFilePath(), {"--clipboard-owner", "native"});
                check(owner.waitForStarted(), "External Wayland clipboard source starts");
                output.clear();
                wait(
                    [&] {
                        output += owner.readAllStandardOutput();
                        return output.contains("ready\n");
                    },
                    "External Wayland source copies text and HTML");
                wait([&] { return QGuiApplication::focusWindow() == &window; },
                     "Clipboard fixture regains native focus");
                processFor(100);
                js("nativePaste=null");
                view->browser()->GetMainFrame()->Paste();
                wait([&] { return js("!!nativePaste").toBool(); }, "External Wayland paste arrives in Chromium");
                check(js("nativePaste.text").toString() == QStringLiteral("External Wayland α\n二") &&
                          js("nativePaste.html").toString() == "<b>External Wayland</b>",
                      "External Wayland text and HTML survive Chromium paste");
                owner.terminate();
                owner.waitForFinished(2000);
                input.ready = false;
                wait([&] { return input.ready; }, "Fresh input authorizes image clipboard copy");
                QImage image(24, 24, QImage::Format_ARGB32);
                image.fill(Qt::red);
                clipboard->setImage(image);
                processFor(100);
                js("nativePaste=null");
                view->browser()->GetMainFrame()->Paste();
                wait([&] { return js("!!nativePaste").toBool(); }, "Wayland image paste arrives");
                check(js("nativePaste.files").toInt() == 1, "Native Wayland images reach Chromium");
                puts("PASS: external/native Wayland text, HTML, PNG, opaque custom formats and lazy 16 MiB transfers");
            } catch (const std::exception &error) {
                failure = QString::fromUtf8(error.what());
                fprintf(stderr, "Clipboard check failed: %s\n", error.what());
            }
            if (owner.state() != QProcess::NotRunning) {
                owner.terminate();
                owner.waitForFinished(2000);
            }
            // A newer input serial authorizes restoring the previous selection.
            input.ready = false;
            QElapsedTimer restoreInput;
            restoreInput.start();
            while (!input.ready && restoreInput.elapsed() < 5000)
                processFor(5);
            clipboard->setMimeData(saved.release());
            processFor(300);
            view->setParentItem(nullptr);
            object.reset();
            window.close();
            ReSketchCef::shutdown();
            require(failure.isEmpty(), qPrintable(failure));
            return 0;
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
        // Run --clipboard on an isolated X display: these cases own CLIPBOARD.
        if (clipboardBenchmark) {
            js("window.maxPasteGap=0;window.lastPasteTick=performance.now();"
               "window.pasteHeartbeat=setInterval(()=>{const now=performance.now();maxPasteGap=Math.max(maxPasteGap,now-lastPasteTick);lastPasteTick=now},10);"
               "addEventListener('paste',e=>{window.pasteTextSize=e.clipboardData.getData('text/plain').length;"
               "window.pasteHtmlSize=e.clipboardData.getData('text/html').length;window.pasteFiles=[...e.clipboardData.files].map(f=>f.size)})");
            for (const auto &kind : {"text", "html", "image"}) {
                QProcess owner;
                auto environment = QProcessEnvironment::systemEnvironment();
                environment.insert("QT_QPA_PLATFORM", "xcb");
                owner.setProcessEnvironment(environment);
                owner.start(app.applicationFilePath(), {"--clipboard-owner", kind});
                require(owner.waitForStarted() && owner.waitForReadyRead(15000), "External clipboard owner ready");
                require(owner.readLine().trimmed() == "ready", "External clipboard payload ready");
                const int previous = js("pastes").toInt();
                js("window.maxPasteGap=0;window.lastPasteTick=performance.now()");
                QElapsedTimer duration;
                duration.start();
                view->browser()->GetMainFrame()->Paste();
                until([&] { return js("pastes").toInt() > previous; }, "Large native clipboard paste completes", 30000);
                require(duration.elapsed() < 1500, "Clipboard transport does not stall for seconds");
                require(js("maxPasteGap").toDouble() < 1500, "Renderer stays responsive during large paste");
                fprintf(stderr, "CLIPBOARD: %s paste %lld ms; renderer gap %.0f ms; text %d html %d files %s\n",
                    kind, duration.elapsed(), js("maxPasteGap").toDouble(), js("pasteTextSize").toInt(),
                    js("pasteHtmlSize").toInt(), qPrintable(js("JSON.stringify(pasteFiles)").toString()));
                if (QByteArray(kind) == "text") require(js("pasteTextSize").toInt() == 4 * 1024 * 1024, "Large text paste is intact");
                if (QByteArray(kind) == "html") require(js("pasteHtmlSize").toInt() >= 4 * 1024 * 1024, "Large HTML paste is intact");
                if (QByteArray(kind) == "image") require(js("pasteFiles.length").toInt() == 1, "Image paste is intact");
                owner.terminate();
                owner.waitForFinished();
            }
            const int requestedMiB = qEnvironmentVariableIntValue("RESKETCH_CLIPBOARD_MIB");
            const int internalMiB = qBound(1, requestedMiB > 0 ? requestedMiB : 4, 64);
            const int internalBytes = internalMiB * 1024 * 1024;
            js(QStringLiteral("window.copies=0;addEventListener('copy',e=>{e.preventDefault();copies++;"
               "e.clipboardData.setData('text/plain','z'.repeat(%1));"
               "e.clipboardData.setData('text/html','<b>'+ 'w'.repeat(%1)+'</b>')})").arg(internalBytes));
            QElapsedTimer roundTrip;
            roundTrip.start();
            const auto shortcut = [view](Qt::Key key) {
                QKeyEvent down(QEvent::KeyPress, key, Qt::ControlModifier);
                QKeyEvent up(QEvent::KeyRelease, key, Qt::ControlModifier);
                QCoreApplication::sendEvent(view, &down);
                QCoreApplication::sendEvent(view, &up);
            };
            shortcut(Qt::Key_C);
            until([&] { return js("copies").toInt() == 1; }, "Large native browser copy completes");
            const int previous = js("pastes").toInt();
            shortcut(Qt::Key_V);
            until([&] { return js("pastes").toInt() > previous; }, "Large native browser round trip completes");
            fprintf(stderr, "CLIPBOARD: internal %d MiB text/HTML copy and paste %lld ms\n", internalMiB, roundTrip.elapsed());
            require(roundTrip.elapsed() < 1500 && js("pasteHtmlSize").toInt() >= internalBytes
                        && js("pasteTextSize").toInt() == internalBytes,
                    "Large internal copy/paste is fast and preserves HTML");
            js("clearInterval(pasteHeartbeat)");
            timespec beforeIdle{}, afterIdle{};
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &beforeIdle);
            QElapsedTimer idle;
            idle.start();
            while (idle.elapsed() < 400) {
                QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
                QThread::msleep(1);
            }
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &afterIdle);
            const double idleCpuMs = (afterIdle.tv_sec - beforeIdle.tv_sec) * 1000.0
                + (afterIdle.tv_nsec - beforeIdle.tv_nsec) / 1e6;
            require(idleCpuMs < idle.elapsed() / 2.0, "Native event wakeups do not spin while idle");
            fprintf(stderr, "CLIPBOARD: idle main-thread CPU %.1f%%\n", 100 * idleCpuMs / idle.elapsed());
            if (hasArgument("--clipboard-only")) {
                view->setParentItem(nullptr);
                object.reset();
                window.close();
                ReSketchCef::shutdown();
                return 0;
            }
        }
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
        const auto snapshot = [&] {
            auto grab = view->grabToImage();
            bool ready = false;
            QObject::connect(grab.get(), &QQuickItemGrabResult::ready, [&] { ready = true; });
            until([&] { return ready; }, "resize frame capture");
            return grab->image();
        };
        const auto viewport = [&] {
            CefRect rect;
            view->browser()->GetHost()->GetClient()->GetRenderHandler()->GetViewRect(view->browser(), rect);
            return QSize(rect.width, rect.height);
        };
        js("window.liveResizeWidths=[];window.liveResizeListener=()=>liveResizeWidths.push(innerWidth);addEventListener('resize',liveResizeListener)");
        int resizeSteps = 0;
        QTimer liveResize;
        liveResize.setInterval(16);
        QObject::connect(&liveResize, &QTimer::timeout, [&] {
            ++resizeSteps;
            const QSize size(400 + resizeSteps % 24 * 12, 300 + resizeSteps % 24 * 6);
            window.resize(size);
            view->setSize(size);
            require(viewport() == size, "focused resize reaches CEF synchronously for every geometry change");
        });
        liveResize.start();
        until([&] { return resizeSteps >= 8; }, "continuous focused resizing");
        require(js("liveResizeWidths.length>1 && liveResizeWidths.some(width=>width>400)").toBool(),
                "Chromium relayout runs while the window is still being resized");
        require(liveResize.isActive(), "foreground relayout does not wait for resize to finish");
        until([&] {
            const auto frame = snapshot();
            return frame.width() > 420 && frame.pixelColor(420,180).blue() > 180;
        }, "focused tab paints newly exposed canvas pixels during continuous resizing");
        liveResize.stop();
        js("removeEventListener('resize',liveResizeListener)");
        window.resize(400,300);
        view->setSize(QSizeF(400,300));
        until([&] { return js("innerWidth===400 && innerHeight===300").toBool(); }, "viewport restored after live resizing");
        until([&] { return snapshot().pixelColor(100,220).blue() > 180; }, "paint restored after continuous resizing");
        view->setLifecycleState(CefQuickView::LifecycleState::Frozen);
        window.resize(600,450);
        view->setSize(QSizeF(600,450));
        const auto pendingResize = snapshot();
        require(pendingResize.pixelColor(100,180).blue() > 180
                && pendingResize.pixelColor(100,120).red() > 180,
                "pending frames retain native scale rather than stretching during resize");
        require(pendingResize.pixelColor(500,200).alpha() == 0,
                "old frames are clipped and do not stretch across newly exposed space");
        view->setLifecycleState(CefQuickView::LifecycleState::Active);
        until([&] { return js("innerWidth===600 && innerHeight===450").toBool(); }, "foreground resize reaches Chromium");
        until([&] { return snapshot().pixelColor(500,200).blue() > 180; }, "fresh resized frame fills the viewport");
        const int foregroundFrameRate = view->browser()->GetHost()->GetWindowlessFrameRate();
        view->setVisible(false);
        view->setSize(QSizeF(680,490));
        view->setSize(QSizeF(700,500));
        require(viewport() == QSize(600,450), "background tab resize yields to foreground work");
        processFor(40);
        require(viewport() == QSize(600,450), "background resizing is throttled");
        until([&] { return viewport() == QSize(700,500); }, "background tabs quietly reach the latest viewport");
        until([&] { return js("innerWidth===700 && innerHeight===500").toBool(); }, "hidden Chromium layout reaches the background viewport");
        until([&] { return view->browser()->GetHost()->GetWindowlessFrameRate() == foregroundFrameRate; }, "background render completes and restores its frame budget");
        require(!view->isVisible(), "background rendering never reveals the tab in Qt");
        // Freeze before revealing it so capture cannot be repaired by a new
        // foreground paint. The resized pixels must already exist offscreen.
        view->setLifecycleState(CefQuickView::LifecycleState::Frozen);
        view->setVisible(true);
        require(snapshot().pixelColor(650,200).blue() > 180, "background pixels are resized before tab activation");
        view->setVisible(false);
        view->setSize(QSizeF(740,520));
        until([&] { return viewport() == QSize(740,520); }, "sleeping loaded tabs resize without activation");
        until([&] { return view->browser()->GetHost()->GetWindowlessFrameRate() == foregroundFrameRate; }, "sleeping background resize completes");
        require(view->lifecycleState() == CefQuickView::LifecycleState::Frozen, "background resize preserves the requested sleeping state");
        const int slept = js("ticks").toInt();
        processFor(100);
        require(js("ticks").toInt() == slept, "resized sleeping tabs return to frozen timers");
        view->setVisible(true);
        require(snapshot().pixelColor(715,200).blue() > 180, "sleeping tabs also cache fresh background pixels");
        view->setLifecycleState(CefQuickView::LifecycleState::Active);
        view->setVisible(false);
        view->setSize(QSizeF(720,520));
        view->setVisible(true);
        require(viewport() == QSize(720,520), "activating a tab immediately flushes its pending resize");
        window.resize(400,300);
        view->setSize(QSizeF(400,300));
        until([&] { return js("innerWidth===400 && innerHeight===300").toBool(); }, "restored viewport");
        until([&] { return snapshot().pixelColor(100,220).blue() > 180; }, "restored frame");
        fprintf(stderr, "Native-scale resizing, foreground priority and background resize coalescing passed\n");
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
        // Figma's numeric scrub controls fall back to captured pointer movement
        // when pointer lock is unavailable, without creating a virtual cursor.
        js(R"JS(
            window.scrubValue=20;window.scrubbing=false;window.scrubStart=0;
            const scrub=document.createElement('div');scrub.id='scrub';
            scrub.style.cssText='position:absolute;left:100px;top:80px;width:120px;height:30px;cursor:ew-resize';
            document.body.appendChild(scrub);
            scrub.onpointerdown=e=>{
                if(scrub.requestPointerLock)throw Error('Unsupported pointer-lock path selected');
                scrubbing=true;scrubStart=e.clientX;scrub.setPointerCapture(e.pointerId);
            };
            scrub.onpointermove=e=>{if(scrubbing)scrubValue=20+e.clientX-scrubStart};
            scrub.onpointerup=e=>{scrubbing=false;scrub.releasePointerCapture(e.pointerId)};
        )JS");
        QMouseEvent scrubPress(QEvent::MouseButtonPress, QPointF(110,90), QPointF(110,90),
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(view, &scrubPress);
        until([&] { return js("scrubbing").toBool(); }, "Numeric scrub starts without pointer lock");
        QMouseEvent scrubMove(QEvent::MouseMove, QPointF(250,90), QPointF(250,90),
                             Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(view, &scrubMove);
        until([&] { return js("scrubValue").toInt()==160; }, "Captured numeric scrub continues outside its field");
        QMouseEvent beyondScreen(QEvent::MouseMove, QPointF(20000,90), QPointF(20000,90),
                                Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(view, &beyondScreen);
        until([&] { return js("scrubValue").toInt()==19910; }, "Captured numeric scrub accepts unbounded client coordinates");
        QMouseEvent scrubRelease(QEvent::MouseButtonRelease, QPointF(250,90), QPointF(250,90),
                                Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(view, &scrubRelease);
        until([&] { return !js("scrubbing").toBool(); }, "Numeric scrub releases cleanly");
        js("document.getElementById('scrub').remove()");
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
        // Wayland's primary pointer can be a touchpad; this case needs a mouse.
        QPointingDevice fixtureMouse("Fixture mouse", 102, QInputDevice::DeviceType::Mouse,
            QPointingDevice::PointerType::Generic, QInputDevice::Capability::Position | QInputDevice::Capability::Scroll, 1, 3);
        QWheelEvent mouseWheel(QPointF(200, 200), QPointF(200, 200), QPoint(), QPoint(0, -120), Qt::NoButton,
                               Qt::NoModifier, Qt::NoScrollPhase, false, Qt::MouseEventNotSynthesized, &fixtureMouse);
        QCoreApplication::sendEvent(view, &mouseWheel);
        const int wheelDistance = 40 * QGuiApplication::styleHints()->wheelScrollLines();
        until([&] { return js("scrollY").toInt() >= wheelDistance; }, "mouse wheel scrolling");
        const auto samples =
            js(QString("scrollSamples.filter(y=>y>0 && y<%1).length").arg(wheelDistance)).toInt();
        fprintf(stderr, "Wheel animation intermediate samples: %d\n", samples);
        require(samples >= 2, "Chromium mouse wheel scrolling animates through intermediate positions");
        js("document.body.insertAdjacentHTML('beforeend','<aside class=fb-sidebar id=homeScroll style=\"position:fixed;left:0;top:0;width:150px;height:280px;overflow:auto;z-index:1000\"><div style=\"height:3000px\"></div></aside>');"
           "window.homeWheels=[];homeScroll.addEventListener('wheel',e=>{e.preventDefault();homeWheels.push(e.deltaY);homeScroll.scrollTop+=e.deltaY},{passive:false})");
        QPointingDevice pad("Fixture touchpad", 101, QInputDevice::DeviceType::TouchPad,
            QPointingDevice::PointerType::Finger, QInputDevice::Capability::Position | QInputDevice::Capability::Scroll, 2, 0);
        const auto homeWheel = [&](QPoint pixels, Qt::ScrollPhase phase, bool inverted = false) {
            QWheelEvent event(QPointF(80,160), QPointF(80,160), pixels, {}, Qt::NoButton, Qt::NoModifier,
                              phase, inverted, Qt::MouseEventSynthesizedBySystem, &pad);
            QCoreApplication::sendEvent(view, &event);
        };
        processFor(120); // Commit the new sidebar to Chromium’s hit-test tree.
        QMouseEvent homeMove(QEvent::MouseMove, QPointF(80,160), QPointF(80,160), Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(view, &homeMove);
        homeWheel({}, Qt::ScrollBegin);
        for (int i = 0; i < 3; ++i) { homeWheel(QPoint(0,-24), Qt::ScrollUpdate); processFor(20); }
        const int heldScroll = js("homeScroll.scrollTop").toInt();
        require(heldScroll == 72, "Trackpad stays attached to finger motion in the Home sidebar");
        homeWheel({}, Qt::ScrollEnd);
        until([&] { return js("homeScroll.scrollTop").toInt() > heldScroll + 10; }, "Home sidebar continues with inertia after release");
        homeWheel({}, Qt::ScrollBegin);
        processFor(40);
        const int stoppedScroll = js("homeScroll.scrollTop").toInt();
        processFor(100);
        require(js("homeScroll.scrollTop").toInt() == stoppedScroll, "A new touch stops synthesized inertia");
        homeWheel(QPoint(0,-12), Qt::ScrollMomentum);
        homeWheel({}, Qt::ScrollEnd);
        processFor(200);
        require(js("homeScroll.scrollTop").toInt() == stoppedScroll + 12, "Platform momentum is not duplicated");
        homeWheel(QPoint(0,10), Qt::ScrollUpdate, true);
        until([&] { return js("homeScroll.scrollTop").toInt() == stoppedScroll + 2; }, "System natural-scroll direction is preserved");
        homeWheel({}, Qt::ScrollEnd);
        processFor(150);
        const int beforeMouse = js("homeScroll.scrollTop").toInt();
        js("homeWheels=[]");
        QWheelEvent homeMouse(QPointF(80,160), QPointF(80,160), {}, QPoint(0,-120), Qt::NoButton,
                              Qt::NoModifier, Qt::NoScrollPhase, false, Qt::MouseEventNotSynthesized, &fixtureMouse);
        QCoreApplication::sendEvent(view, &homeMouse);
        until([&] { return js("homeScroll.scrollTop").toInt() == beforeMouse + wheelDistance; }, "Mouse scrolling retains its full distance");
        require(js("homeWheels.length>=3").toBool(), "Custom Figma/Home wheel handlers receive smooth mouse steps");
        view->settings()->setProperty("scrollAnimatorEnabled", false);
        view->settings()->setProperty("inertialScrollingEnabled", false);
        const int noEffectsStart = js("homeScroll.scrollTop").toInt();
        js("homeWheels=[]");
        QCoreApplication::sendEvent(view, &homeMouse);
        until([&] { return js("homeScroll.scrollTop").toInt() == noEffectsStart + wheelDistance; }, "Disabled mouse smoothing still scrolls");
        require(js("homeWheels.length").toInt() == 1, "Disabling smoothing sends one mouse step");
        view->settings()->setProperty("mouseScrollSensitivity", 500);
        const int maximumSpeedStart = js("homeScroll.scrollTop").toInt();
        QCoreApplication::sendEvent(view, &homeMouse);
        until([&] { return js("homeScroll.scrollTop").toInt() == maximumSpeedStart + wheelDistance * 5; }, "Maximum scroll sensitivity sends the full 500 percent distance");
        view->settings()->setProperty("mouseScrollSensitivity", 200);
        const int sensitivityStart = js("homeScroll.scrollTop").toInt();
        QCoreApplication::sendEvent(view, &homeMouse);
        until([&] { return js("homeScroll.scrollTop").toInt() == sensitivityStart + wheelDistance * 2; }, "Mouse sensitivity scales Chromium wheel distance");
        homeWheel(QPoint(0, -12), Qt::ScrollUpdate);
        until([&] { return js("homeScroll.scrollTop").toInt() == sensitivityStart + wheelDistance * 2 + 24; }, "Scroll sensitivity scales trackpad pixels too");
        const int precisionStart = js("homeScroll.scrollTop").toInt();
        QWheelEvent precisionMouse(QPointF(80,160), QPointF(80,160), QPoint(0,-12), {}, Qt::NoButton,
                                  Qt::NoModifier, Qt::NoScrollPhase, false, Qt::MouseEventNotSynthesized, &fixtureMouse);
        QCoreApplication::sendEvent(view, &precisionMouse);
        until([&] { return js("homeScroll.scrollTop").toInt() == precisionStart + 24; }, "Precision mouse pixels use scroll sensitivity");
        const int phasedMouseStart = js("homeScroll.scrollTop").toInt();
        QWheelEvent phasedMouse(QPointF(80,160), QPointF(80,160), {}, QPoint(0,-120), Qt::NoButton,
                               Qt::NoModifier, Qt::ScrollUpdate, false, Qt::MouseEventNotSynthesized, &fixtureMouse);
        QCoreApplication::sendEvent(view, &phasedMouse);
        until([&] { return js("homeScroll.scrollTop").toInt() == phasedMouseStart + wheelDistance * 2; }, "Mouse wheels with scroll phases use scroll sensitivity");
        view->settings()->setProperty("inertialScrollingEnabled", true);
        const int momentumStart = js("homeScroll.scrollTop").toInt();
        homeWheel(QPoint(0, -12), Qt::ScrollMomentum);
        until([&] { return js("homeScroll.scrollTop").toInt() == momentumStart + 24; }, "Scroll sensitivity also scales platform momentum");
        view->settings()->setProperty("inertialScrollingEnabled", false);
        view->settings()->setProperty("mouseScrollSensitivity", 25);
        homeWheel({}, Qt::ScrollBegin);
        const int slowStart = js("homeScroll.scrollTop").toInt();
        for (int i = 0; i < 16; ++i) homeWheel(QPoint(0, -1), Qt::ScrollUpdate);
        until([&] { return js("homeScroll.scrollTop").toInt() == slowStart + 4; }, "Low sensitivity preserves subpixel scrolling");
        QWheelEvent zoomWheel(QPointF(80,160), QPointF(80,160), QPoint(0,-12), {}, Qt::NoButton,
                             Qt::ControlModifier, Qt::ScrollUpdate, false, Qt::MouseEventSynthesizedBySystem, &pad);
        QCoreApplication::sendEvent(view, &zoomWheel);
        until([&] { return js("homeScroll.scrollTop").toInt() == slowStart + 16; }, "Scroll sensitivity leaves Ctrl wheel zoom unchanged");
        view->settings()->setProperty("mouseScrollSensitivity", 100);
        homeWheel({}, Qt::ScrollBegin);
        for(int i=0; i<3; ++i) { homeWheel(QPoint(0,-12), Qt::ScrollUpdate); processFor(20); }
        homeWheel({}, Qt::ScrollEnd);
        const int noInertia = js("homeScroll.scrollTop").toInt();
        processFor(200);
        require(js("homeScroll.scrollTop").toInt() == noInertia, "Disabled inertia has no synthetic tail");
        homeWheel(QPoint(0,-24), Qt::ScrollMomentum);
        processFor(100);
        require(js("homeScroll.scrollTop").toInt() == noInertia, "Disabled inertia also ignores platform momentum");
        view->settings()->setProperty("inertialScrollingEnabled", true);
        homeWheel({}, Qt::ScrollBegin);
        for(int i=0; i<3; ++i) { homeWheel(QPoint(0,-12), Qt::ScrollUpdate); processFor(20); }
        homeWheel({}, Qt::ScrollEnd);
        until([&] { return js("homeScroll.scrollTop").toInt() > noInertia + 40; }, "Inertia works independently of mouse smoothing");
        view->settings()->setProperty("scrollAnimatorEnabled", true);
        js("homeScroll.remove()");
        fprintf(stderr, "PASS: Home sidebar finger tracking, inertia, cancellation, platform momentum and smooth mouse scrolling\n");
        // Exercise Qt -> Chromium drag delivery and its HTML drop data.
        js("scrollTo(0,0);window.dropped='';window.dragLeft=false;window.dragOvers="
           "0;"
           "document.body.addEventListener('dragover',e=>{e.preventDefault();"
           "window.dragOvers++;e.dataTransfer.dropEffect='copy'});"
           "document.body.addEventListener('dragleave',()=>window.dragLeft=true);"
           "document.body.addEventListener('drop',e=>{e.preventDefault();window."
           "dropped=e.dataTransfer.getData('text/plain')})");
        until([&] { return js("scrollY===0").toBool(); }, "drag fixture scroll position");
        QMimeData dragMime;
        dragMime.setText("layer-drag-fixture");
        const QPoint dropPosition(200, 100);
        QDragEnterEvent dragEnter(dropPosition, Qt::CopyAction, &dragMime, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(&window, &dragEnter);
        require(dragEnter.isAccepted(), "Web view accepts native drag entry");
        QDragMoveEvent dragMove(dropPosition, Qt::CopyAction, &dragMime, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(&window, &dragMove);
        until([&] { return js("dragOvers>0").toBool(); }, "HTML target accepts native drag motion");
        QDropEvent drop(dropPosition, Qt::CopyAction, &dragMime, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(&window, &drop);
        until([&] { return js("dropped").toString() == "layer-drag-fixture"; },
              "HTML drop receives native payload");
        QDragEnterEvent secondEnter(dropPosition, Qt::CopyAction, &dragMime, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(&window, &secondEnter);
        QDragLeaveEvent leave;
        QCoreApplication::sendEvent(&window, &leave);
        until([&] { return js("dragLeft").toBool(); }, "Leaving the view clears HTML drag state");
        fprintf(stderr, "PASS: native drag/drop payload and cancellation\n");
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
        CefTaskMonitor taskMonitor;
        require(!taskMonitor.active() && taskMonitor.resourceUsage(view).isEmpty(), "Hidden task monitor does no sampling");
        taskMonitor.setActive(true);
        until([&] { return taskMonitor.resourceUsage(view).value("memory").toDouble() > 0; },
              "Chromium task manager publishes a real memory sample");
        const auto idleResources = taskMonitor.resourceUsage(view);
        const auto taskId = idleResources.value("taskId").toLongLong();
        const double idleMemory = idleResources.value("memory").toDouble();
        js("window.taskMemory=new Uint8Array(48*1024*1024);taskMemory.fill(17);"
           "window.resourceBurn=setInterval(()=>{const end=performance.now()+35;while(performance.now()<end){}},50)");
        until([&] {
            const auto usage = taskMonitor.resourceUsage(view);
            return usage.value("memory").toDouble() > idleMemory + 24 && usage.value("cpu").toDouble() > 10;
        }, "Task samples track real renderer CPU work and resident allocation");
        const double busyCpu = taskMonitor.resourceUsage(view).value("cpu").toDouble();
        require(taskMonitor.resourceUsage(view).value("taskId").toLongLong() == taskId,
                "Resource samples stay associated with the correct browser task");
        js("clearInterval(resourceBurn);delete window.taskMemory");
        until([&] { return taskMonitor.resourceUsage(view).value("cpu").toDouble() < busyCpu * 0.8; },
              "CPU samples fall after renderer work stops");
        fprintf(stderr, "PASS: live Chromium task samples (idle %.1f MiB, busy %.1f%% CPU)\n", idleMemory, busyCpu);
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
        require(taskMonitor.resourceUsage(view).isEmpty(), "Unloaded tabs do not retain stale task samples");
        taskMonitor.setActive(false);
        require(!taskMonitor.active() && taskMonitor.resourceUsage(view).isEmpty(), "Closing task manager stops sampling");
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
