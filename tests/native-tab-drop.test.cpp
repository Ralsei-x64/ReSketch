// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

// Reuse the app's generated moc; build with tests/check-native-tab-drop.sh.
#define main resketchMain
#include "../src/main.cpp"
#undef main
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QEventLoop>
#include <QMimeData>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonArray>
#include <QJsonDocument>
#include <QUrlQuery>
#include <QQmlComponent>
#include <QTemporaryDir>
#include <QWheelEvent>
#include <QPointingDevice>
#include <QQuickItem>
#include <QSGNode>
#include <cassert>

class PaintProbe : public QQuickItem {
public:
    explicit PaintProbe(QQuickItem *parent) : QQuickItem(parent)
    {
        setFlag(ItemHasContents);
        setSize(QSizeF(40, 40));
    }
    int paints = 0;
protected:
    QSGNode *updatePaintNode(QSGNode *node, UpdatePaintNodeData *) override
    {
        ++paints;
        return node ? node : new QSGNode;
    }
};

int main(int argc, char **argv)
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QtWebEngineQuick::initialize();
    QApplication app(argc, argv);
    QTemporaryDir temporary;
    assert(temporary.isValid());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, temporary.path());
    assert(requestedSafeMode({QStringLiteral("resketch"), QStringLiteral("--safe-mode")}));
    {
        QSettings saved(QStringLiteral("aether64"), QStringLiteral("ReSketch"));
        saved.setValue(QStringLiteral("exportHistory"), QVariantList{QVariantMap{{"name", "export.png"}}});
        saved.setValue(QStringLiteral("exportFolders/document"), temporary.path());
        saved.setValue(QStringLiteral("obsoleteSetting"), true);
        AppSettings recovery(nullptr, true);
        recovery.setUseVulkan(true);
        recovery.setChromiumFlags(QStringLiteral("--enable-features=Vulkan"));
        recovery.setFigmaCustomCss(QStringLiteral("body { color: red; }"));
        recovery.setTheme(QStringLiteral("dark"));
        assert(recovery.safeMode() && recovery.useVulkan()); // Saved values remain editable.
        assert(QGuiApplication::styleHints()->colorScheme() != Qt::ColorScheme::Dark);
        QQmlApplicationEngine recoveryEngine;
        recoveryEngine.rootContext()->setContextProperty("appSettings", &recovery);
        recoveryEngine.load(QUrl::fromLocalFile(QDir::current().absoluteFilePath("src/SettingsWindow.qml")));
        assert(!recoveryEngine.rootObjects().isEmpty());
        auto *resetButton = recoveryEngine.rootObjects().first()->findChild<QObject *>("resetSettingsButton");
        auto *cssEditor = recoveryEngine.rootObjects().first()->findChild<QObject *>("customCssEditor");
        assert(resetButton && cssEditor);
        cssEditor->setProperty("text", QStringLiteral("pending CSS edit"));
        assert(QMetaObject::invokeMethod(resetButton, "clicked"));
        assert(cssEditor->property("text").toString().isEmpty());
        assert(recovery.theme() == QStringLiteral("auto") && !recovery.useVulkan());
        assert(recovery.gpuRasterization() && recovery.chromiumFlags().isEmpty());
        assert(recovery.figmaCustomCss().isEmpty() && recovery.exportHistory().size() == 1);
        assert(saved.value(QStringLiteral("exportFolders/document")).toString() == temporary.path());
        assert(!saved.contains(QStringLiteral("obsoleteSetting")));
        assert(saved.value(QStringLiteral("settingsInitialized")).toBool());
    }
    puts("Safe-mode recovery and settings reset preserve export data and discard pending CSS checks passed");
    AppSettings settings;
    {
        FontHelper helper(nullptr, 0);
        assert(helper.port());
        QNetworkAccessManager network;
        const auto get = [&](const QString &path, const QByteArray &origin = "https://www.figma.com", const QByteArray &method = "GET") {
            QNetworkRequest request(QUrl(QStringLiteral("http://127.0.0.1:%1%2").arg(helper.port()).arg(path)));
            if (!origin.isEmpty()) request.setRawHeader("Origin", origin);
            auto *reply = network.sendCustomRequest(request, method);
            QEventLoop loop;
            QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
            QTimer::singleShot(10000, &loop, &QEventLoop::quit);
            loop.exec();
            assert(reply->isFinished());
            const auto result = qMakePair(reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(), reply->readAll());
            if (result.first == 200 || result.first == 204) {
                assert(reply->rawHeader("Access-Control-Allow-Origin") == origin);
                assert(reply->rawHeader("Access-Control-Allow-Private-Network") == "true");
            }
            delete reply;
            return result;
        };
        assert(get("/figma/version").first == 200);
        assert(get("/figma/font-files", {}, "GET").first == 403);
        assert(get("/figma/font-files", "https://figma.com.evil.test").first == 403);
        assert(get("/figma/font-files", "http://figma.com").first == 403);
        assert(get("/figma/font-files", "https://www.figma.com", "OPTIONS").first == 204);
        const auto catalog = get("/figma/font-files?freetype_minimum_api_version=20&isolate=true");
        assert(catalog.first == 200);
        const auto files = QJsonDocument::fromJson(catalog.second).object().value("fontFiles").toObject();
        assert(!files.isEmpty());
        for (auto it = files.begin(); it != files.end(); ++it) {
            assert(!it.value().toArray().isEmpty());
            for (const auto &value : it.value().toArray()) {
                const auto face = value.toObject();
                assert(!face.value("family").toString().isEmpty() && !face.value("style").toString().isEmpty());
                assert(!face.value("postscript").toString().isEmpty());
                assert(face.value("weight").toInt() > 0 && face.value("stretch").toInt() >= 1 && face.value("stretch").toInt() <= 9);
                for (const auto &value : face.value("variationAxes").toArray()) {
                    const auto axis = value.toObject();
                    assert(axis.value("tag").toString().size() == 4);
                    assert(axis.value("min").toDouble() <= axis.value("value").toDouble());
                    assert(axis.value("max").toDouble() >= axis.value("value").toDouble());
                }
            }
        }
        const auto path = files.begin().key();
        QFile font(path);
        assert(font.open(QIODevice::ReadOnly));
        const auto bytes = get("/figma/font-file?file=" + QString::fromLatin1(QUrl::toPercentEncoding(path)));
        assert(bytes.first == 200 && bytes.second == font.readAll());
        assert(get("/figma/font-file?file=/etc/passwd").first == 404);
        assert(get("/figma/unknown").first == 404);
        printf("Local font catalog, metadata, byte loading, origin checks, preflight and file allowlist passed (%d font files)\n", files.size());
    }
    {
        const QString file = QStringLiteral("https://www.figma.com/design/File_A/My-File?node-id=1-2");
        const QStringList candidates{file, QStringLiteral("about:blank"), QStringLiteral("https://www.figma.com/desktop_new_tab"),
                                     QStringLiteral("https://www.figma.com/files/recent"), QStringLiteral("https://figma.com.evil.test/design/bad"),
                                     QStringLiteral("http://figma.com/design/bad"), QStringLiteral("https://user@figma.com/design/bad")};
        assert(!settings.rememberOpenedTabs());
        QWindow sessionWindow;
        sessionWindow.setProperty("sessionFileUrls", candidates);
        settings.registerMainWindow(&sessionWindow);
        settings.setRememberOpenedTabs(true);
        settings.saveOpenedTabs(&sessionWindow);
        AppSettings nextLaunch;
        assert(nextLaunch.rememberedFileTabs() == QStringList{file});
        settings.setRememberOpenedTabs(false);
        settings.setRememberOpenedTabs(true);
        assert(settings.rememberedFileTabs().isEmpty());
        settings.setRememberOpenedTabs(false);
        puts("File-only session persistence, defaults and disabling checks passed");
    }
    settings.setMenuIntegration(false);
    settings.setReduceMotion(true);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("appSettings", &settings);
    QQmlComponent profile(&engine);
    profile.setData("import QtWebEngine; WebEngineProfile { offTheRecord: true }", QUrl());
    QObject *sharedProfile = profile.create();
    assert(sharedProfile);
    sharedProfile->setParent(&engine);
    engine.setInitialProperties({{"sharedProfile", QVariant::fromValue(sharedProfile)}});
    engine.load(QUrl::fromLocalFile(QDir::current().absoluteFilePath("src/Main.qml")));
    assert(!engine.rootObjects().isEmpty());
    auto *destination = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    assert(destination);
    engine.globalObject().setProperty("destination", engine.newQObject(destination));
    const auto evaluate = [&](const QString &script) {
        const auto result = engine.evaluate(script);
        if (result.isError()) qFatal("%s", qPrintable(result.toString()));
        return result;
    };
    const auto render = [] {
        QEventLoop loop;
        QTimer::singleShot(100, &loop, &QEventLoop::quit);
        loop.exec();
    };
    evaluate("destination.homeView.stop(); destination.openTab('https://www.figma.com/design/Live_A/Live-File', null, true); destination.views[0].stop();");
    settings.setRememberOpenedTabs(true);
    settings.saveOpenedTabs(destination);
    assert(settings.rememberedFileTabs() == QStringList{QStringLiteral("https://www.figma.com/design/Live_A/Live-File")});
    evaluate("destination.views[0].url = 'about:blank'; destination.views[0].stop();");
    settings.saveOpenedTabs(destination);
    assert(settings.rememberedFileTabs().isEmpty());
    // Exercise the real close event, not just the save helper.
    evaluate("destination.views[0].url = 'https://www.figma.com/board/Live_B/Live-Board'; destination.views[0].stop();");
    destination->close();
    assert(settings.rememberedFileTabs() == QStringList{QStringLiteral("https://www.figma.com/board/Live_B/Live-Board")});
    destination->show();
    settings.setRememberOpenedTabs(false);
    evaluate("destination.closeTab(0);");
    puts("Live QML session URL tracking and window-close persistence checks passed");
    {
        QQuickItem container(destination->contentItem());
        PaintProbe probe(&container);
        render();
        const int before = probe.paints;
        assert(before > 0);
        settings.repaintWebView(&container);
        render();
        assert(probe.paints > before); // The child repaint does not require pointer input.
        container.setVisible(false);
        render();
        const int hidden = probe.paints;
        settings.repaintWebView(&container);
        render();
        assert(probe.paints == hidden);
    }
    puts("Visible web content repaints without pointer input; hidden views remain idle");
    evaluate("destination.homeView.stop(); destination.openTab('about:blank'); destination.openTab('about:blank');"
             "var source = destination.moveTabToNewWindow(0); source.homeView.stop(); var movedView = source.activeView;");
    render();
    evaluate("source.beginItemDrag(movedView, source.browserContent, Qt.point(80, 20));");
    const auto token = evaluate("source.dragToken").toString().toUtf8();
    assert(!token.isEmpty());
    QMimeData mime;
    mime.setData("application/x-resketch-tab", token);
    QDragEnterEvent enter(QPoint(150, 100), Qt::MoveAction, &mime, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(destination, &enter);
    assert(enter.isAccepted());
    QDropEvent drop(QPointF(150, 100), Qt::MoveAction, &mime, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(destination, &drop);
    assert(drop.isAccepted() && drop.dropAction() == Qt::MoveAction);
    assert(evaluate("destination.tabDragSession.targetWindow === destination").toBool());
    evaluate("source.finishNativeTabDrag(Qt.MoveAction);");
    render();
    assert(evaluate("movedView.ownerWindow === destination && destination.views.length === 2 && destination.detachedWindows.length === 0").toBool());
    puts("Native tab MIME drop, live transfer, and empty-window closing checks passed");

    assert(!settings.gpuAccelerationWarning().isEmpty()); // This check runs with Qt's software backend.
    assert(isSoftwareRenderer(QStringLiteral("llvmpipe (LLVM 20.1, 256 bits)")));
    assert(isSoftwareRenderer(QStringLiteral("Google SwiftShader")));
    assert(!isSoftwareRenderer(QStringLiteral("AMD Radeon Graphics (radeonsi, LLVM 20.1)")));
    assert(evaluate("destination.contentItem.children.length > 0").toBool());
    puts("Software renderer detection and acceleration warning checks passed");

    evaluate("for (var i = 0; i < 10; ++i) destination.openTab('about:blank', null, true);"
             "destination.views.forEach(view => view.stop());");
    render();
    auto *tabs = destination->findChild<QQuickItem *>(QStringLiteral("tabsViewport"));
    auto *overview = destination->findChild<QQuickItem *>(QStringLiteral("overviewFlickable"));
    assert(tabs && overview);
    QPointingDevice touchpad(QStringLiteral("Test touchpad"), 42, QInputDevice::DeviceType::TouchPad,
                             QPointingDevice::PointerType::Finger, QInputDevice::Capability::Position | QInputDevice::Capability::Scroll,
                             2, 0);
    const auto wheel = [&](QQuickItem *item, QPoint pixels, QPoint angles, Qt::ScrollPhase phase,
                           bool inverted = false, const QPointingDevice *device = nullptr) {
        if (!device) device = &touchpad;
        const QPointF local = item->mapToScene(QPointF(item->width() / 2, item == tabs ? 20 : 200));
        QWheelEvent event(local, destination->mapToGlobal(local), pixels, angles, Qt::NoButton, Qt::NoModifier,
                          phase, inverted, device == &touchpad ? Qt::MouseEventSynthesizedBySystem : Qt::MouseEventNotSynthesized,
                          device);
        QCoreApplication::sendEvent(destination, &event);
    };
    const auto position = [](QQuickItem *item, const char *property) { return item->property(property).toDouble(); };
    tabs->setProperty("contentX", 300.0);
    wheel(tabs, {}, {}, Qt::ScrollBegin);
    wheel(tabs, QPoint(-64, -8), QPoint(-120, -30), Qt::ScrollUpdate);
    assert(qAbs(position(tabs, "contentX") - 364) < 1); // Use pixels, once, even for a large diagonal movement.
    wheel(tabs, QPoint(-2, -40), QPoint(-4, -80), Qt::ScrollUpdate);
    assert(qAbs(position(tabs, "contentX") - 366) < 1); // Keep the gesture's original axis.
    wheel(tabs, QPoint(-24, -1), {}, Qt::ScrollMomentum);
    assert(qAbs(position(tabs, "contentX") - 390) < 1);
    wheel(tabs, {}, {}, Qt::ScrollEnd);
    wheel(tabs, {}, {}, Qt::ScrollBegin);
    wheel(tabs, QPoint(1, 80), QPoint(3, 120), Qt::ScrollUpdate, true);
    assert(qAbs(position(tabs, "contentX") - 310) < 1); // Respect already-inverted platform deltas.
    wheel(tabs, {}, {}, Qt::ScrollEnd);
    wheel(tabs, {}, QPoint(-30, 0), Qt::ScrollUpdate);
    assert(qAbs(position(tabs, "contentX") - 365) < 1); // Angle-only touchpad fallback.
    wheel(tabs, {}, {}, Qt::ScrollEnd);
    evaluate("destination.toggleOverview();");
    render();
    overview->setProperty("contentY", 100.0);
    wheel(overview, {}, {}, Qt::ScrollBegin);
    wheel(overview, QPoint(-20, -64), QPoint(-50, -120), Qt::ScrollUpdate);
    assert(qAbs(position(overview, "contentY") - 164) < 1);
    wheel(overview, QPoint(0, -16), {}, Qt::ScrollMomentum);
    assert(qAbs(position(overview, "contentY") - 180) < 1);
    wheel(overview, {}, {}, Qt::ScrollEnd);
    settings.setReduceMotion(false);
    wheel(overview, {}, QPoint(0, -120), Qt::NoScrollPhase, false, QPointingDevice::primaryPointingDevice());
    assert(overview->property("smoothWheel").toBool()); // Mouse wheel retains its easing.
    wheel(overview, {}, {}, Qt::ScrollBegin);
    assert(!overview->property("smoothWheel").toBool()); // A new gesture stops old mouse-wheel easing.
    puts("Native trackpad axes, pixels, momentum, natural scrolling, and mouse-wheel easing checks passed");
}
