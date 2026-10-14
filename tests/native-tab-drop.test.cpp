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
#include <QTcpServer>
#include <QTcpSocket>
#include <cassert>

// Capture requests to the compositor, including when tests run without KWin.
static QRegion requestedBlurRegion;
static bool requestedBlurEnabled = false;
static QWindow *blurProbe = nullptr;
static QList<bool> blurRequests;
namespace KWindowEffects {
void enableBlurBehind(QWindow *window, bool enable, const QRegion &region)
{
    requestedBlurRegion = region;
    requestedBlurEnabled = enable;
    if (window == blurProbe) blurRequests.append(enable);
}
}

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
    qputenv("RESKETCH_CEF_FLAGS", "--disable-gpu --no-sandbox");
    QApplication app(argc, argv);
    QTemporaryDir temporary;
    assert(temporary.isValid());
    qputenv("RESKETCH_CEF_CACHE_ROOT", (temporary.path()+"/cef").toUtf8());
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
    {
        AppSettings toolbar;
        const auto defaults = toolbar.toolbarItems();
        assert(defaults.size() == 8);
        assert(std::count_if(defaults.cbegin(), defaults.cend(), [](const QVariant &item) {
            return item.toMap().value("enabled").toBool();
        }) == 4);
        auto configured = defaults;
        configured.move(4, 0);
        auto exports = configured.first().toMap();
        exports["enabled"] = true;
        configured[0] = exports;
        toolbar.setToolbarItems(configured);
        AppSettings persisted;
        assert(persisted.toolbarItems() == configured);
        toolbar.setToolbarItems({exports, exports, QVariantMap{{"id", "unknown"}},
                                 QVariantMap{{"id", "menu"}, {"enabled", false}}});
        const auto normalized = toolbar.toolbarItems();
        assert(normalized.size() == defaults.size());
        assert(normalized[0].toMap().value("id") == "export-history");
        assert(normalized[1].toMap().value("id") == "menu");
        assert(!normalized[1].toMap().value("enabled").toBool());
        toolbar.resetSettings();
        assert(toolbar.toolbarItems() == defaults);
        puts("Toolbar order, visibility, persistence, normalization and reset checks passed");
    }
    {
        AppSettings shortcuts;
        assert(shortcuts.shortcutOverrides().isEmpty());
        shortcuts.setShortcutOverrides({{"new-tab", "Ctrl+Y"}, {"overview-left", ""}, {"invalid", "NotAKey"}});
        AppSettings persisted;
        assert(persisted.shortcutOverrides() == shortcuts.shortcutOverrides());
        assert(shortcuts.shortcutOverrides().value("new-tab") == "Ctrl+Y");
        assert(shortcuts.shortcutOverrides().contains("overview-left"));
        assert(!shortcuts.shortcutOverrides().contains("invalid"));
        assert(shortcuts.shortcutSequenceText(QKeySequence("Ctrl+Y")) == "Ctrl+Y");
        assert(shortcuts.keyEventSequence(Qt::Key_Right, Qt::ShiftModifier) == "Shift+Right");
        assert(shortcuts.keyEventSequence(Qt::Key_Enter, Qt::KeypadModifier) == "Enter");
        shortcuts.setShortcutOverrides({});
        assert(shortcuts.shortcutOverrides().isEmpty());
        shortcuts.setShortcutOverrides({{"new-tab", "Ctrl+Y"}});
        shortcuts.resetSettings();
        assert(shortcuts.shortcutOverrides().isEmpty());
        puts("Shortcut persistence, validation, clearing and reset checks passed");
    }
    {
        const QString proc = temporary.path() + "/proc";
        const auto write = [](const QString &path, const QByteArray &bytes) {
            assert(QDir().mkpath(QFileInfo(path).absolutePath()));
            QFile file(path);
            assert(file.open(QIODevice::WriteOnly));
            assert(file.write(bytes) == bytes.size());
        };
        write(proc + "/1/task/1/children", "2 3");
        write(proc + "/1/task/9/children", "2 4"); // Child launched from another thread; duplicate PID.
        write(proc + "/2/task/2/children", "5");
        write(proc + "/1/smaps_rollup", "Rss: 999999 kB\nPss: 1024 kB\nPss_Anon: 900 kB\n");
        write(proc + "/2/smaps_rollup", "Pss: 2048 kB\n");
        write(proc + "/3/smaps_rollup", "Pss: 4096 kB\n");
        write(proc + "/4/smaps_rollup", "Pss: 8192 kB\n");
        write(proc + "/5/smaps_rollup", "Pss: 16384 kB\n");
        assert(appProcessMemoryMiB(1, proc) == 31);
        write(proc + "/5/smaps_rollup", "");
        write(proc + "/5/statm", "100 2 1");
        assert(appProcessMemoryMiB(1, proc) == 15 + 2.0 * sysconf(_SC_PAGESIZE) / (1024 * 1024));
        assert(appProcessMemoryMiB(QCoreApplication::applicationPid()) > 0);
    }
    puts("Whole-process-family memory accounting, shared memory and fallback checks passed");
    puts("Safe-mode recovery and settings reset preserve export data and discard pending CSS checks passed");
    AppSettings settings;
    assert(!settings.floatingSidebars() && settings.sidebarCornerRadius() == 12 && settings.sidebarMargin() == 8 && settings.hideFloatingScrollbars());
    settings.setFloatingSidebars(true);
    settings.setSidebarCornerRadius(22);
    settings.setSidebarMargin(16);
    settings.setHideFloatingScrollbars(false);
    {
        AppSettings persisted;
        assert(persisted.floatingSidebars() && persisted.sidebarCornerRadius() == 22 && persisted.sidebarMargin() == 16 && !persisted.hideFloatingScrollbars());
    }
    settings.setSidebarMargin(99);
    assert(settings.sidebarMargin() == 40);
    settings.setSidebarMargin(-1);
    assert(settings.sidebarMargin() == 0);
    settings.setSidebarCornerRadius(99);
    assert(settings.sidebarCornerRadius() == 40);
    settings.setSidebarCornerRadius(-1);
    assert(settings.sidebarCornerRadius() == 0);
    settings.resetSettings();
    assert(!settings.floatingSidebars() && settings.sidebarCornerRadius() == 12 && settings.sidebarMargin() == 8 && settings.hideFloatingScrollbars());
    {
        QQuickWindow window;
        settings.registerMainWindow(&window);
        window.resize(1280, 800);
        window.setProperty("chromiumFrameLoaded", false);
        window.setProperty("tabStripHeight", 40);
        settings.setToolbarOpacity(60);
        settings.refreshWindowBlur(&window);
        assert(requestedBlurEnabled && requestedBlurRegion.isEmpty());
        window.showFullScreen();
        window.resize(2560, 1440);
        settings.refreshWindowBlur(&window);
        assert(requestedBlurEnabled && requestedBlurRegion.isEmpty()); // Whole-window hint has no stale bounds.
        window.setProperty("chromiumFrameLoaded", true);
        settings.refreshWindowBlur(&window);
        assert(requestedBlurRegion == QRegion(0, 0, window.width(), 40)); // The platform controls fullscreen geometry.
        settings.setFloatingSidebars(true);
        settings.refreshWindowBlur(&window);
        assert(requestedBlurRegion == QRegion(0, 0, window.width(), 40)); // Home does not float.
        window.setProperty("floatingFileSidebars", true);
        settings.refreshWindowBlur(&window);
        assert(requestedBlurEnabled && requestedBlurRegion.isEmpty()); // Only the floating surfaces reveal the desktop.
        settings.setFloatingSidebars(false);
        settings.setTranslucentSidebars(true);
        settings.refreshWindowBlur(&window);
        assert(requestedBlurRegion.isEmpty()); // Transparent sidebars need the whole surface too.
        blurProbe = &window;
        blurRequests.clear();
        QEventLoop loop;
        QTimer::singleShot(200, &loop, &QEventLoop::quit);
        loop.exec();
        assert(blurRequests.contains(false) && !blurRequests.isEmpty() && blurRequests.last());
        assert(requestedBlurRegion.isEmpty()); // Reapply after the resized frame, clearing cached compositor bounds.
        blurProbe = nullptr;
        settings.setIgnoreToolbarBlur(true);
        settings.refreshWindowBlur(&window);
        assert(!requestedBlurEnabled);
        settings.setIgnoreToolbarBlur(false);
        settings.setTranslucentSidebars(false);
        settings.setToolbarOpacity(100);
        settings.refreshWindowBlur(&window);
        assert(!requestedBlurEnabled);
    }
    puts("Fullscreen and resized window blur hints, toolbar bounds, sidebar coverage and disable checks passed");
    {
        CefPermission permission(QUrl("https://www.figma.com"), CefPermission::PermissionType::LocalFontsAccess);
        permission.grant();assert(permission.accepted);permission.deny();assert(!permission.accepted);
        auto *notification=new CefNotification("Untrusted", "Must be rejected", QUrl("http://127.0.0.1"), "1", nullptr);
        bool closed=false;QObject::connect(notification,&CefNotification::closed,[&]{closed=true;});
        settings.showDesktopNotification(notification,nullptr);assert(closed);
    }
    puts("CEF permission control and untrusted native notification rejection checks passed");
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
        assert(settings.deferRestoredTabs());
        settings.setDeferRestoredTabs(false);
        { AppSettings nextLaunch; assert(!nextLaunch.deferRestoredTabs()); }
        settings.setDeferRestoredTabs(true);
        QWindow sessionWindow;
        sessionWindow.setProperty("sessionFileUrls", candidates);
        sessionWindow.setProperty("sessionTabGroups", QVariantList{
            QVariantMap{{"title", "Design work"}, {"color", "#4477aa"}, {"icon", "applications-graphics"}, {"collapsed", true},
                        {"overviewCollapsed", true}, {"tabs", QVariantList{0, 1, -1, 999}}},
            QVariantMap{{"title", "Empty"}, {"color", "#cc4455"}, {"tabs", QVariantList{1}}}});
        settings.registerMainWindow(&sessionWindow);
        settings.setRememberOpenedTabs(true);
        settings.saveOpenedTabs(&sessionWindow);
        AppSettings nextLaunch;
        assert(nextLaunch.rememberedFileTabs() == QStringList{file});
        auto groups = nextLaunch.rememberedTabGroups();
        assert(groups.size() == 1);
        assert(groups.first().toMap().value("title").toString() == "Design work");
        assert(groups.first().toMap().value("color").toString() == "#4477aa");
        assert(groups.first().toMap().value("icon").toString() == "applications-graphics");
        assert(groups.first().toMap().value("collapsed").toBool());
        assert(groups.first().toMap().value("overviewCollapsed").toBool());
        assert(groups.first().toMap().value("tabs").toList() == QVariantList{0});
        QWindow secondWindow;
        const QString secondFile = QStringLiteral("https://www.figma.com/board/File_B/Other-File");
        secondWindow.setProperty("sessionFileUrls", QStringList{secondFile});
        secondWindow.setProperty("sessionTabGroups", QVariantList{
            QVariantMap{{"title", "Other window"}, {"color", "#cc4455"}, {"tabs", QVariantList{0}}}});
        settings.registerMainWindow(&secondWindow);
        secondWindow.show();
        settings.saveOpenedTabs(&sessionWindow);
        groups = nextLaunch.rememberedTabGroups();
        assert(groups.size() == 2);
        const auto savedFiles = nextLaunch.rememberedFileTabs();
        assert(savedFiles.size() == 2);
        for (const auto &entry : groups) {
            const auto group = entry.toMap();
            const int index = group.value("tabs").toList().first().toInt();
            assert(savedFiles[index] == (group.value("title").toString() == "Design work" ? file : secondFile));
        }
        settings.setRememberOpenedTabs(false);
        settings.setRememberOpenedTabs(true);
        assert(settings.rememberedFileTabs().isEmpty());
        assert(settings.rememberedTabGroups().isEmpty());
        settings.setRememberOpenedTabs(false);
        puts("File/group session persistence, multi-window membership, empty groups and disabling checks passed");
    }
    {
        AppSettings budget;
        assert(budget.memoryLimitMiB() == 0);
        budget.setMemoryLimitMiB(32768);
        AppSettings savedBudget;
        assert(savedBudget.memoryLimitMiB() == 32768);
        QQmlEngine budgetEngine;
        QQmlComponent windowComponent(&budgetEngine);
        windowComponent.setData(R"(
            import QtQuick
            Window {
                property double usedAt: 0
                property QtObject page: QtObject { property bool sleepCapturePending: false; property bool unloaded: false }
                property var memoryTabCandidates: page.unloaded ? [] : [{view: page, lastUsedAt: usedAt}]
                function unloadTabForMemory(view) { if (view !== page) return false; view.unloaded = true; return true }
            }
        )", QUrl());
        std::unique_ptr<QObject> newer(windowComponent.create());
        std::unique_ptr<QObject> older(windowComponent.create());
        assert(newer && older);
        newer->setProperty("usedAt", 200);
        older->setProperty("usedAt", 100);
        budget.registerMainWindow(newer.get());
        budget.registerMainWindow(older.get());
        auto *newPage = newer->property("page").value<QObject *>();
        auto *oldPage = older->property("page").value<QObject *>();
        assert(newPage && oldPage);
        budget.finishMemoryCheck(32769);
        assert(oldPage->property("unloaded").toBool() && !newPage->property("unloaded").toBool());
        assert(budget.totalAppMemoryMiB() == 32769);
        budget.finishMemoryCheck(32767);
        assert(!newPage->property("unloaded").toBool()); // Stop as soon as total falls below the budget.
        oldPage->setProperty("sleepCapturePending", true);
        budget.finishMemoryCheck(32769);
        assert(!newPage->property("unloaded").toBool()); // Wait for pending capture instead of mass unloading.
        oldPage->setProperty("sleepCapturePending", false);
        budget.finishMemoryCheck(32769);
        assert(newPage->property("unloaded").toBool());
        budget.setMemoryLimitMiB(0);
        newPage->setProperty("unloaded", false);
        budget.finishMemoryCheck(99999);
        assert(!newPage->property("unloaded").toBool());
    }
    puts("Global LRU memory budget across windows, remeasurement, pending capture and unlimited checks passed");
    settings.setMenuIntegration(false);
    settings.setReduceMotion(true);
    QQmlApplicationEngine engine;
    engine.addImportPath(QDir::current().absoluteFilePath("build-cef/qml"));
    engine.rootContext()->setContextProperty("appSettings", &settings);
    QQmlComponent profile(&engine);
    profile.setData("import ReSketch.Cef; CefProfile { offTheRecord: true }", QUrl());
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
    evaluate("destination.homeView.stop(); for (let i = 0; i < 3; ++i) { destination.openTab('about:blank', null, true); destination.views[i].stop(); }"
             "destination.views[0].lastUsedAt = 200; destination.views[1].lastUsedAt = 100; destination.views[2].lastUsedAt = 300;");
    render();
    settings.setMemoryLimitMiB(32768);
    settings.finishMemoryCheck(32769);
    assert(evaluate("destination.views[1].memoryUnloaded && !destination.views[0].memoryUnloaded && !destination.views[2].memoryUnloaded").toBool());
    render();
    assert(evaluate("destination.views[1].lifecycleState === 2").toBool());
    settings.finishMemoryCheck(32767);
    assert(!evaluate("destination.views[0].memoryUnloaded").toBool());
    evaluate("destination.activateTab(1, false);");
    assert(!evaluate("destination.views[1].memoryUnloaded").toBool());
    settings.setMemoryLimitMiB(0);
    evaluate("destination.views.slice().reverse().forEach(view => destination.closeTab(destination.views.indexOf(view)));");
    for (int i = 0; i < 10 && evaluate("destination.views.length").toInt(); ++i) render();
    assert(evaluate("destination.views.length").toInt() == 0);
    puts("Native memory controller unloads real QML CEF tabs and selection restores them");
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
    evaluate("destination.openTab('https://www.figma.com/design/Deferred_A/Deferred-File', null, true, null, null, true);");
    settings.setRememberOpenedTabs(true);
    settings.saveOpenedTabs(destination);
    assert(settings.rememberedFileTabs() == QStringList{QStringLiteral("https://www.figma.com/design/Deferred_A/Deferred-File")});
    assert(evaluate("String(destination.views[destination.views.length - 1].deferredRestoreUrl)").toString() == settings.rememberedFileTabs().first());
    settings.setRememberOpenedTabs(false);
    evaluate("destination.closeTab(destination.views.length - 1);");
    render();
    puts("Deferred restored tabs retain their file URL for the next session");
    evaluate("destination.openTab('https://www.figma.com/design/Group_A/First', null, true, null, null, true);"
             "destination.openTab('https://www.figma.com/design/Group_B/Second', null, true, null, null, true);"
             "var savedGroup = destination.createTabGroup(destination.views[0], 'Saved group', '#4477aa', 'applications-graphics');"
             "destination.assignTabGroup(destination.views[1], savedGroup);"
             "destination.updateTabGroup(savedGroup, {collapsed: true, overviewCollapsed: true}, true);");
    evaluate("destination.homeView.loadHtml('<html><body>Local task-manager probe</body></html>');");
    for (int attempt = 0; attempt < 50 && evaluate("destination.homeView.renderProcessPid").toInt() <= 0; ++attempt)
        render();
    const qint64 rendererPid = evaluate("destination.homeView.renderProcessPid").toNumber();
    assert(rendererPid > 0);
    const auto resources = settings.chromiumTabResources();
    assert(!resources.isEmpty());
    bool haveRenderer = false;
    for (const auto &value : resources) {
        const auto task = value.toMap();
        const auto pid = task.value("pid").toLongLong();
        assert(pid > 0 && pid != QCoreApplication::applicationPid());
        assert(task.value("memory").toDouble() >= 0 && task.value("cpu").toDouble() >= 0);
        if (pid == rendererPid) haveRenderer = true;
    }
    assert(haveRenderer);
    puts("Tab task manager measures live tab renderers and excludes the app process");
    evaluate("destination.chooseTabGroupIcon(savedGroup);");
    bool iconPickerOpened = false;
    for (int attempt = 0; attempt < 20 && !iconPickerOpened; ++attempt) {
        render();
        for (auto *widget : QApplication::topLevelWidgets()) {
            if (widget->isVisible() && widget->windowTitle() == QStringLiteral("Tab group icon")) {
                iconPickerOpened = true;
                widget->close();
                break;
            }
        }
    }
    assert(iconPickerOpened);
    assert(evaluate("destination.groupFor(destination.views[0]).icon").toString() == "applications-graphics");
    puts("Native KDE group icon picker opens and cancel preserves the selected icon");
    settings.setRememberOpenedTabs(true);
    settings.saveOpenedTabs(destination);
    assert(settings.rememberedTabGroups().size() == 1);
    assert(settings.rememberedTabGroups().first().toMap().value("tabs").toList() == (QVariantList{0, 1}));
    {
        QQmlComponent restoredComponent(&engine, QUrl::fromLocalFile(QDir::current().absoluteFilePath("src/Main.qml")));
        std::unique_ptr<QObject> restored(restoredComponent.createWithInitialProperties({{"sharedProfile", QVariant::fromValue(sharedProfile)}}));
        assert(restored);
        engine.globalObject().setProperty("restoredSession", engine.newQObject(restored.get()));
        assert(evaluate("restoredSession.tabGroups.length").toInt() == 1);
        assert(evaluate("restoredSession.tabGroups[0].title").toString() == "Saved group");
        assert(evaluate("restoredSession.tabGroups[0].icon").toString() == "applications-graphics");
        assert(evaluate("String(restoredSession.tabGroups[0].color)").toString() == "#4477aa");
        assert(evaluate("restoredSession.tabGroups[0].collapsed && restoredSession.tabGroups[0].overviewCollapsed").toBool());
        assert(evaluate("restoredSession.views.length === 2 && restoredSession.views[0].tabGroupId === restoredSession.views[1].tabGroupId").toBool());
        assert(evaluate("restoredSession.views.every(view => String(view.deferredRestoreUrl).includes('/design/'))").toBool());
        evaluate("restoredSession.homeView.stop(); restoredSession.close();");
    }
    evaluate("for (const view of destination.views.slice()) destination.closeTab(destination.views.indexOf(view));");
    render();
    settings.saveOpenedTabs(destination);
    assert(settings.rememberedTabGroups().isEmpty());
    assert(evaluate("destination.tabGroups.length").toInt() == 0);
    settings.setRememberOpenedTabs(false);
    puts("Live QML group session serialization and last-member removal checks passed");
    {
        QQuickItem container(destination->contentItem());
        PaintProbe probe(&container);
        render();
        const int before = probe.paints;
        assert(before > 0);
        settings.repaintWebView(&container);
        render();
        assert(probe.paints > before); // The child repaint does not require pointer input.
        const int firstFrame = probe.paints;
        render();
        assert(probe.paints > firstFrame); // Also refresh after asynchronous theme/mask updates.
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
