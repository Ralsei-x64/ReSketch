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
#include <QNativeGestureEvent>
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
#include <QTest>

void checkUpdates();

void checkSettingsNavigation(QQuickWindow *window, AppSettings &settings)
{
    const QSize originalSize = window->size();
    const bool originalMotion = settings.reduceMotion();
    auto *navigation = window->findChild<QQuickItem *>("settingsNavigation");
    auto *viewport = window->findChild<QQuickItem *>("settingsSectionViewport");
    auto *body = window->findChild<QQuickItem *>("settingsSectionBody");
    auto *slide = window->findChild<QObject *>("settingsSectionSlide");
    auto *animation = window->findChild<QObject *>("settingsSectionTransition");
    auto *defaults = window->findChild<QQuickItem *>("resetSettingsButton");
    assert(navigation && viewport && body && slide && animation && defaults);
    settings.setReduceMotion(true);
    window->show();
    for (const auto size : {QSize(650, 420), QSize(880, 700)}) {
        window->resize(size);
        window->setProperty("selectedSection", 0);
        QTest::qWait(50);
        const qreal paneWidth = viewport->width();
        for (int section = 0; section < 9; ++section) {
            window->setProperty("selectedSection", section);
            QTest::qWait(30);
            assert(navigation->width() == 164);
            assert(viewport->width() == paneWidth && paneWidth > 0);
        }
    }
    const auto footerPosition = defaults->mapToScene(QPointF());
    window->setProperty("selectedSection", 0);
    settings.setReduceMotion(false);
    window->setProperty("selectedSection", 1);
    QTest::qWait(40);
    assert(animation->property("running").toBool());
    assert(slide->property("x").toReal() > 0 && slide->property("x").toReal() <= 24);
    assert(body->opacity() >= 0.7 && body->opacity() < 1);
    assert(defaults->mapToScene(QPointF()) == footerPosition);
    QTest::qWait(220);
    assert(!animation->property("running").toBool() && slide->property("x").toReal() == 0 && body->opacity() == 1);
    window->setProperty("selectedSection", 0);
    QTest::qWait(40);
    assert(slide->property("x").toReal() < 0);
    for (int section : {8, 3, 7}) window->setProperty("selectedSection", section);
    QTest::qWait(240);
    assert(window->property("selectedSection").toInt() == 7 && slide->property("x").toReal() == 0);
    window->setProperty("selectedSection", 1);
    settings.setReduceMotion(true);
    assert(!animation->property("running").toBool() && slide->property("x").toReal() == 0 && body->opacity() == 1);
    window->hide();
    window->setProperty("selectedSection", 0);
    window->resize(originalSize);
    settings.setReduceMotion(originalMotion);
    puts("Settings: stable sizing at minimum/default sizes, forward/backward slides, rapid switches, stationary footer and reduced motion passed");
}


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
    setbuf(stdout, nullptr);
    setbuf(stderr, nullptr);
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    qputenv("RESKETCH_CEF_FLAGS", "--disable-gpu --no-sandbox");
    KIconTheme::initTheme();
    QApplication app(argc, argv);
    if (app.arguments().contains(QStringLiteral("--icons"))) {
        // This invocation has no external icon themes in its data paths.
        QIcon::setThemeSearchPaths({QStringLiteral(":/icons")});
        QIcon::setFallbackSearchPaths({});
        QIcon::setThemeName(QStringLiteral("resketch-missing-icon-theme"));
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nimport org.kde.kirigami as Kirigami\n"
                          "Kirigami.Icon { width:22; height:22; source: \"tab-new\" }", QUrl());
        std::unique_ptr<QObject> probe(component.create());
        assert(probe);
        for (const auto *name : {"tab-new", "view-grid", "view-refresh", "application-menu", "go-home",
                                "window-close", "window-minimize", "window-maximize", "window-restore",
                                "go-previous", "go-next", "go-up", "go-down", "arrow-left", "arrow-right", "arrow-down",
                                "configure", "folder", "folder-open", "text-x-generic", "document-export", "document-open",
                                "edit-copy", "edit-delete", "edit-rename", "edit-clear-all", "edit-find", "edit-undo",
                                "overflow-menu", "system-suspend", "help-about", "dialog-password", "color-management",
                                "preferences-desktop-theme", "preferences-desktop-notification", "preferences-desktop-keyboard",
                                "preferences-desktop-icons", "preferences-system-performance", "tab-duplicate",
                                "applications-development", "view-process-system", "view-process-all", "tools-report-bug",
                                "view-visible", "process-stop", "drag-handle-symbolic"}) {
            const QIcon icon = QIcon::fromTheme(QString::fromLatin1(name));
            assert(!icon.isNull() && !icon.pixmap(22, 22).isNull());
            probe->setProperty("source", QString::fromLatin1(name));
            QCoreApplication::processEvents();
            assert(probe->property("valid").toBool());
        }
        assert(QIcon::fromTheme(QStringLiteral("window-close")).pixmap(22, 22).toImage()
               != QIcon::fromTheme(QStringLiteral("window-minimize")).pixmap(22, 22).toImage());
        puts("Native and Kirigami icons render with no installed icon themes, using distinct embedded fallbacks");
        return 0;
    }
    QTemporaryDir temporary;
    assert(temporary.isValid());
    qputenv("RESKETCH_CEF_CACHE_ROOT", (temporary.path()+"/cef").toUtf8());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, temporary.path());
    if (app.arguments().contains(QStringLiteral("--streamer")) || app.arguments().contains(QStringLiteral("--streamer-preview"))) {
        QCoreApplication::setApplicationVersion(QStringLiteral("1.5.2"));
        AppSettings settings;
        auto *streamer = settings.streamer();
        assert(!streamer->enabled());
        assert(streamer->maximumEntries() == 8);
        assert(streamer->style().value("windowWidth").toInt() == 384 && streamer->style().value("windowHeight").toInt() == 328);
        streamer->setStyle({{"windowWidth", -1}, {"windowHeight", 10000}});
        assert(streamer->style().value("windowWidth").toInt() == 200 && streamer->style().value("windowHeight").toInt() == 2160);
        streamer->setStyle({{"paddingX", 19}, {"paddingY", 7}});
        assert(streamer->style().value("paddingLeft").toInt() == 19
            && streamer->style().value("paddingRight").toInt() == 19
            && streamer->style().value("paddingTop").toInt() == 7
            && streamer->style().value("paddingBottom").toInt() == 7);
        streamer->setStyle({{"paddingX", 19}, {"paddingLeft", 3}});
        assert(streamer->style().value("paddingLeft").toInt() == 3
            && streamer->style().value("paddingRight").toInt() == 19);
        streamer->setStyle({});
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("appSettings", &settings);
        engine.loadData(R"(
import QtQuick
import QtQuick.Controls
import "../src" as App
ApplicationWindow {
    id: inputWindow
    visible: true; width: 880; height: 700
    property int shortcutsFired: 0
    property int wheelEvents: 0
    property alias streamerBackdrop: inputSurface
    property alias browserContent: webSurface
    TextInput {
        id: inputSurface
        anchors.fill: parent; focus: true
        Item { id: webSurface; y: 90; width: parent.width; height: parent.height - y }
        Rectangle { anchors.fill: parent; color: "white"; z: -2 }
        Repeater {
            model: 30
            Rectangle { required property int index; x: index * 40; width: 20; height: inputSurface.height; color: "#d6badd"; z: -1 }
        }
        WheelHandler { onWheel: event => inputWindow.wheelEvents++ }
    }
    Shortcut { sequence: "Ctrl+K"; onActivated: shortcutsFired++ }
    App.StreamerOverlay { id: overlay; objectName: "overlay"; anchors.fill: parent; targetWindow: Window.window }
    App.StreamerSettings { objectName: "streamerSettings"; visible: false; overlay: overlay }
})", QUrl::fromLocalFile(QDir::current().absoluteFilePath("tests/streamer-fixture.qml")));
        assert(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        if (!app.arguments().contains(QStringLiteral("--streamer-preview")))
            settings.registerMainWindow(window);
        window->requestActivate();
        QTest::qWait(100);
        auto *overlay = window->findChild<QObject *>("overlay");
        auto *queue = window->findChild<QQuickItem *>("streamerKeyQueue");
        const auto count = [&] { return overlay->property("entryCount").toInt(); };
        const auto labels = [&] {
            QStringList result;
            const auto visit = [&](auto &&self, QQuickItem *item) -> void {
                if (item->objectName() == "streamerKeyLabel") result << item->property("text").toString();
                for (auto *child : item->childItems()) self(self, child);
            };
            visit(visit, queue);
            return result;
        };
        if (app.arguments().contains(QStringLiteral("--streamer-preview"))) {
            auto appearance = streamer->style();
            appearance["paddingLeft"] = 17; appearance["paddingRight"] = 23;
            appearance["paddingTop"] = 9; appearance["paddingBottom"] = 15;
            appearance["minWidth"] = 140; appearance["minHeight"] = 72;
            appearance["fontSize"] = 22; appearance["fontFamily"] = "Monospace";
            appearance["alignment"] = 4; appearance["radius"] = 16;
            appearance["blur"] = 24; appearance["transparency"] = 55; appearance["shadow"] = true;
            appearance["sticky"] = true; appearance["horizontalAnchor"] = 2; appearance["verticalAnchor"] = 2;
            appearance["offsetX"] = 0; appearance["offsetY"] = 0;
            streamer->setStyle(appearance);
            streamer->setSpawnDirection(2);
            streamer->setDurationMs(10000);
            streamer->setEnabled(true);
            streamer->pressed(window, QStringLiteral("A"), false);
            streamer->pressed(window, QStringLiteral("W"), false);
            streamer->pressed(window, QStringLiteral("Ctrl + K"), false);
            QTest::qWait(400);
            assert(count() == 3 && queue->height() == 72);
            const auto screenshot = qEnvironmentVariable("RESKETCH_STREAMER_STYLE_SCREENSHOT");
            assert(!screenshot.isEmpty() && window->grabWindow().save(screenshot + ".png"));
            QQmlComponent component(&engine, QUrl::fromLocalFile(QDir::current().absoluteFilePath("src/SettingsWindow.qml")));
            std::unique_ptr<QObject> page(component.create());
            assert(page);
            checkSettingsNavigation(qobject_cast<QQuickWindow *>(page.get()), settings);
            page->setProperty("selectedSection", 7);
            auto *settingsWindow = qobject_cast<QQuickWindow *>(page.get());
            settingsWindow->show();
            QTest::qWait(200);
            assert(settingsWindow->grabWindow().save(screenshot + "-settings.png"));
            auto *scroll = page->findChild<QObject *>("settingsSectionScroll");
            auto *flickable = scroll->property("contentItem").value<QObject *>();
            assert(flickable && flickable->setProperty("contentY", 650));
            QTest::qWait(100);
            assert(settingsWindow->grabWindow().save(screenshot + "-spacing.png"));
            page->setProperty("selectedSection", 6);
            flickable->setProperty("contentY", 0);
            QTest::qWait(150);
            assert(settingsWindow->grabWindow().save(screenshot + "-shortcuts.png"));
            page->setProperty("selectedSection", 0);
            QTest::qWait(150);
            assert(settingsWindow->grabWindow().save(screenshot + "-home.png"));
            const bool previewMotion = settings.reduceMotion();
            settings.setReduceMotion(true);
            for (const QSize size : {QSize(880, 700), QSize(650, 420)}) {
                settingsWindow->resize(size);
                for (int section : {1, 2, 3, 4, 5}) {
                    page->setProperty("selectedSection", section);
                    QTest::qWait(120);
                    const auto name = screenshot + QString("-section-%1-width-%2").arg(section).arg(size.width());
                    assert(settingsWindow->grabWindow().save(name + ".png"));
                    if (size.width() == 880) {
                        flickable->setProperty("contentY", qMax(0.0, flickable->property("contentHeight").toDouble()
                            - flickable->property("height").toDouble()));
                        QTest::qWait(60);
                        assert(settingsWindow->grabWindow().save(name + "-bottom.png"));
                    }
                }
            }
            settings.setReduceMotion(previewMotion);
            // Compare actual pixels over the app UI above the web surface.
            settings.setReduceMotion(true);
            streamer->setEnabled(false);
            appearance["verticalAnchor"] = 0;
            appearance["transparency"] = 100; appearance["blur"] = 0;
            appearance["shadow"] = false; appearance["minWidth"] = 240;
            streamer->setStyle(appearance);
            streamer->setEnabled(true);
            streamer->pressed(window, QStringLiteral("Ctrl + K"), false);
            QTest::qWait(150);
            const auto sharp = window->grabWindow();
            appearance["blur"] = 32;
            streamer->setStyle(appearance);
            QTest::qWait(200);
            const auto blurred = window->grabWindow();
            assert(blurred.save(screenshot + "-app-ui-blur.png"));
            const auto variation = [&](const QImage &frame) {
                const qreal dpr = frame.devicePixelRatio();
                const int y = qRound((queue->y() + 10) * dpr);
                const int left = qRound((queue->x() + 20) * dpr);
                const int right = qRound((queue->x() + queue->width() - 20) * dpr);
                int total = 0;
                for (int x = left + 1; x < right; ++x)
                    total += qAbs(qGray(frame.pixel(x, y)) - qGray(frame.pixel(x - 1, y)));
                return total;
            };
            const int beforeBlur = variation(sharp), afterBlur = variation(blurred);
            printf("App UI blur pixel variation: %d -> %d\n", beforeBlur, afterBlur);
            assert(beforeBlur > 0 && afterBlur < beforeBlur * 0.8);
            puts("Streamer GPU preview: styled keys, horizontal layout, backdrop blur, shadow and settings render");
            return 0;
        }
        QTest::keyClick(window, Qt::Key_A);
        assert(count() == 0);
        streamer->setEnabled(true);
        QTest::keyClick(window, Qt::Key_K, Qt::ControlModifier);
        assert(window->property("shortcutsFired").toInt() == 1);
        assert(count() == 1 && labels() == QStringList{"Ctrl + K"});
        QTest::keyClick(window, Qt::Key_A);
        QTest::keyClick(window, Qt::Key_B);
        assert(count() == 3 && labels() == (QStringList{"Ctrl + K", "A", "B"}));
        QKeyEvent repeat(QEvent::ShortcutOverride, Qt::Key_B, Qt::NoModifier, "b", true, 1);
        QCoreApplication::sendEvent(window, &repeat);
        assert(count() == 3);
        QTest::mouseClick(window, Qt::LeftButton, Qt::ShiftModifier, QPoint(400, 400));
        assert(count() == 4 && labels().last() == "Shift + Mouse Left");
        if (const auto screenshot = qEnvironmentVariable("RESKETCH_STREAMER_SCREENSHOT"); !screenshot.isEmpty())
            assert(window->grabWindow().save(screenshot));
        QQuickWindow unrelated;
        QTest::keyClick(&unrelated, Qt::Key_Z);
        assert(count() == 4);
        streamer->setXPosition(100);
        streamer->setYPosition(0);
        QTest::qWait(200);
        assert(queue->x() == window->width() - queue->width() && queue->y() == 0);
        auto *detach = window->findChild<QObject *>("streamerDetachButton");
        assert(detach && QMetaObject::invokeMethod(detach, "clicked"));
        auto *separate = window->findChild<QWindow *>("streamerOverlayWindow");
        assert(overlay->property("detached").toBool() && separate && separate->isVisible());
        assert(queue->window() == separate);
        assert(separate->size() == QSize(384, 328));
        auto windowDefaults = streamer->style();
        windowDefaults["windowWidth"] = 640; windowDefaults["windowHeight"] = 240;
        streamer->setStyle(windowDefaults);
        assert(separate->size() == QSize(640, 240));
        separate->resize(700, 300);
        windowDefaults["radius"] = 12;
        streamer->setStyle(windowDefaults);
        assert(separate->size() == QSize(700, 300)); // Styling must preserve a manual resize.
        assert(separate->close());
        assert(QMetaObject::invokeMethod(detach, "clicked"));
        assert(separate->size() == QSize(640, 240)); // A fresh detach uses the saved defaults.
        assert(separate->close());
        assert(!overlay->property("detached").toBool() && queue->window() == window);
        QTest::qWait(1500);
        assert(count() == 4);
        assert(queue->childItems().first()->childItems().first()->opacity() < 1);
        QTest::qWait(400);
        assert(count() == 0);
        QTest::keyPress(window, Qt::Key_Control);
        QTest::qWait(1700);
        QTest::keyPress(window, Qt::Key_C, Qt::ControlModifier);
        assert(count() == 1 && labels().last() == "Ctrl + C");
        QTest::keyRelease(window, Qt::Key_C, Qt::ControlModifier);
        QTest::keyRelease(window, Qt::Key_Control);
        QTest::qWait(350);
        assert(count() == 0); // Completing a combo must not extend its two-second lifetime.
        QTest::keyClick(window, Qt::Key_C);
        assert(count() == 1);
        streamer->setEnabled(false);
        assert(count() == 0 && !overlay->property("visible").toBool());
        AppSettings restored;
        assert(!restored.streamer()->enabled() && restored.streamer()->xPosition() == 100 && restored.streamer()->yPosition() == 0);
        auto *durationSlider = window->findChild<QObject *>("streamerDurationSlider");
        assert(durationSlider && durationSlider->property("value").toInt() == 2000);
        durationSlider->setProperty("value", 1500);
        assert(QMetaObject::invokeMethod(durationSlider, "moved"));
        assert(streamer->durationMs() == 1500 && restored.streamer()->durationMs() == 1500);
        streamer->setEnabled(true);
        QTest::keyClick(window, Qt::Key_A);
        auto *entry = queue->childItems().first()->childItems().first();
        assert(entry->scale() >= 0.88 && entry->scale() < 1);
        QTest::qWait(300);
        assert(qAbs(entry->scale() - 1) < 0.001);
        streamer->setDurationMs(500);
        QTest::keyClick(window, Qt::Key_B);
        QTest::qWait(600);
        assert(count() == 1 && labels() == QStringList{"A"}); // Short entries expire before older long entries.
        streamer->setEnabled(false);
        settings.setReduceMotion(true);
        streamer->setEnabled(true);
        QTest::keyClick(window, Qt::Key_B);
        assert(queue->childItems().first()->childItems().first()->scale() == 1);
        QTest::qWait(550);
        assert(count() == 0);
        streamer->setDurationMs(3000);
        QTest::keyPress(window, Qt::Key_Control);
        QTest::qWait(2100);
        QTest::keyClick(window, Qt::Key_C, Qt::ControlModifier);
        QTest::keyRelease(window, Qt::Key_Control);
        assert(count() == 1 && labels() == QStringList{"Ctrl + C"});
        QTest::qWait(950);
        assert(count() == 0);
        streamer->setEnabled(false);
        settings.setReduceMotion(false);
        auto *direction = window->findChild<QObject *>("streamerSpawnDirection");
        assert(direction && direction->property("currentIndex").toInt() == 0);
        direction->setProperty("currentIndex", 1);
        assert(QMetaObject::invokeMethod(direction, "activated", Q_ARG(int, 1)));
        assert(streamer->spawnUpwards() && restored.streamer()->spawnUpwards());
        streamer->setEnabled(true);
        QTest::keyClick(window, Qt::Key_A);
        entry = queue->childItems().first()->childItems().first();
        const int topMargin = 0;
        const auto entryStep = entry->height() + 5;
        assert(entry->y() == topMargin);
        QTest::keyClick(window, Qt::Key_B);
        QTest::qWait(50);
        assert(entry->y() > topMargin && entry->y() < entryStep + topMargin); // Existing keys glide when a new key spawns above them.
        QTest::qWait(160);
        assert(entry->y() == entryStep + topMargin);
        assert(count() == 2 && labels() == (QStringList{"A", "B"}));
        streamer->setSpawnUpwards(false);
        QTest::qWait(200);
        assert(entry->y() == topMargin);
        settings.setReduceMotion(true);
        streamer->setSpawnUpwards(true);
        assert(entry->y() == entryStep + topMargin); // Reduced motion snaps directly to the new placement.
        assert(QMetaObject::invokeMethod(detach, "clicked"));
        QTest::keyClick(window, Qt::Key_C);
        assert(entry->y() == entryStep * 2 + topMargin && queue->window() == separate);
        assert(separate->close());
        streamer->setEnabled(false);
        settings.setReduceMotion(false);
        streamer->setDurationMs(500);
        streamer->setEnabled(true);
        const auto scroll = [&](QWindow *target, QPoint angles, QPoint pixels = {},
                                Qt::KeyboardModifiers modifiers = Qt::NoModifier) {
            QWheelEvent event(QPointF(400, 400), target->mapToGlobal(QPoint(400, 400)), pixels, angles,
                              Qt::NoButton, modifiers, Qt::NoScrollPhase, false);
            QCoreApplication::sendEvent(target, &event);
        };
        scroll(window, QPoint(0, 120));
        assert(count() == 1 && labels().last() == "Scroll: +1");
        scroll(window, QPoint(0, 240));
        assert(count() == 1 && labels().last() == "Scroll: +3");
        scroll(window, QPoint(0, -120));
        assert(labels().last() == "Scroll: +2");
        scroll(window, QPoint(0, -360));
        assert(labels().last() == "Scroll: -1");
        scroll(window, QPoint(0, 120));
        assert(labels().last() == "Scroll: 0");
        scroll(window, QPoint(120, 0));
        scroll(window, {});
        scroll(&unrelated, QPoint(0, 120));
        assert(count() == 1 && labels().last() == "Scroll: 0");
        assert(window->property("wheelEvents").toInt() >= 5); // Capture leaves scrolling available to the UI.
        QTest::keyClick(window, Qt::Key_A);
        scroll(window, {}, QPoint(0, -8));
        assert(count() == 3 && labels().last() == "Scroll: -1");
        QTest::qWait(300);
        scroll(window, {}, QPoint(0, 8));
        assert(count() == 3 && labels().last() == "Scroll: 0");
        QTest::qWait(250);
        assert(count() == 1 && labels().last() == "Scroll: 0"); // Only the active counter's deadline refreshes.
        assert(QMetaObject::invokeMethod(detach, "clicked"));
        scroll(window, QPoint(0, 120));
        assert(count() == 1 && labels().last() == "Scroll: +1" && queue->window() == separate);
        assert(separate->close());
        QTest::qWait(550);
        assert(count() == 0);
        scroll(window, QPoint(0, -120));
        assert(count() == 1 && labels().last() == "Scroll: -1");
        streamer->setEnabled(false);
        scroll(window, QPoint(0, 120));
        assert(count() == 0);
        streamer->setEnabled(true);
        QTest::keyPress(window, Qt::Key_Control);
        scroll(window, QPoint(0, 120), {}, Qt::ControlModifier);
        assert(count() == 1 && labels().last() == "Ctrl + Scroll: +1");
        scroll(window, QPoint(0, 120), {}, Qt::ControlModifier);
        assert(count() == 1 && labels().last() == "Ctrl + Scroll: +2");
        scroll(window, QPoint(0, -360), {}, Qt::ControlModifier);
        assert(count() == 1 && labels().last() == "Ctrl + Scroll: -1");
        QTest::keyPress(window, Qt::Key_Shift, Qt::ControlModifier);
        scroll(window, QPoint(0, 120), {}, Qt::ControlModifier | Qt::ShiftModifier);
        assert(count() == 2 && labels().last() == "Ctrl + Shift + Scroll: +1");
        QTest::keyRelease(window, Qt::Key_Shift, Qt::ControlModifier);
        scroll(window, QPoint(0, 120), {}, Qt::ControlModifier);
        assert(count() == 3 && labels().last() == "Ctrl + Scroll: +1");
        QTest::keyRelease(window, Qt::Key_Control);
        scroll(window, QPoint(0, 120));
        assert(count() == 4 && labels().last() == "Scroll: +1");
        assert(QMetaObject::invokeMethod(detach, "clicked"));
        scroll(window, QPoint(0, 120), {}, Qt::ControlModifier | Qt::AltModifier | Qt::ShiftModifier | Qt::MetaModifier);
        assert(count() == 5 && labels().last() == "Ctrl + Alt + Shift + Meta + Scroll: +1");
        assert(queue->window() == separate && separate->close());
        QTest::qWait(550);
        assert(count() == 0);
        streamer->setEnabled(false);
        auto appearance = streamer->style();
        appearance["marginX"] = 18; appearance["marginY"] = 24;
        appearance["paddingLeft"] = 17; appearance["paddingRight"] = 23;
        appearance["paddingTop"] = 9; appearance["paddingBottom"] = 15;
        appearance["minWidth"] = 140; appearance["minHeight"] = 72;
        appearance["fontFamily"] = "Monospace"; appearance["fontSize"] = 22;
        appearance["background"] = "#123456"; appearance["textColor"] = "#abcdef";
        appearance["radius"] = 14; appearance["transparency"] = 50; appearance["alignment"] = 4;
        appearance["shadow"] = true; appearance["sticky"] = true;
        appearance["horizontalAnchor"] = 1; appearance["verticalAnchor"] = 1;
        appearance["offsetX"] = 30; appearance["offsetY"] = 40;
        streamer->setStyle(appearance);
        streamer->setDurationMs(3000);
        streamer->setSpawnDirection(2);
        settings.setReduceMotion(true);
        streamer->setEnabled(true);
        QTest::keyClick(window, Qt::Key_A);
        QTest::keyClick(window, Qt::Key_W);
        auto *row = queue->childItems().first();
        QList<QQuickItem *> tiles;
        for (auto *child : row->childItems()) if (child->objectName() == "streamerKeyEntry") tiles << child;
        assert(tiles.size() == 2 && tiles[0]->x() == 0 && tiles[1]->x() == tiles[0]->width() + 5);
        assert(tiles[0]->y() == 0 && tiles[1]->y() == 0);
        assert(tiles[0]->width() == 140 && tiles[0]->height() == 72);
        auto *styledLabel = tiles[0]->findChild<QObject *>("streamerKeyLabel");
        auto *surface = tiles[0]->findChild<QObject *>("streamerKeyBackground");
        assert(styledLabel && surface);
        assert(styledLabel->property("font").value<QFont>().pixelSize() == 22);
        assert(styledLabel->property("font").value<QFont>().family() == "Monospace");
        assert(styledLabel->property("color").value<QColor>() == QColor("#abcdef"));
        assert(surface->property("radius").toInt() == 14);
        assert(qAbs(surface->property("color").value<QColor>().alphaF() - 0.5) < 0.01);
        auto *textItem = qobject_cast<QQuickItem *>(styledLabel);
        assert(textItem->x() == 17 && textItem->y() == 9);
        assert(textItem->width() == tiles[0]->width() - 40 && textItem->height() == tiles[0]->height() - 24);
        auto paddingStyle = appearance;
        paddingStyle["minWidth"] = 0; paddingStyle["minHeight"] = 0;
        streamer->setStyle(paddingStyle);
        for (const auto *side : {"paddingTop", "paddingRight", "paddingBottom", "paddingLeft"}) {
            const auto widthBefore = tiles[0]->width(), heightBefore = tiles[0]->height();
            const bool horizontalPadding = QByteArray(side) == "paddingRight" || QByteArray(side) == "paddingLeft";
            paddingStyle[side] = paddingStyle.value(side).toInt() + 7;
            streamer->setStyle(paddingStyle);
            assert(tiles[0]->width() == widthBefore + (horizontalPadding ? 7 : 0));
            assert(tiles[0]->height() == heightBefore + (horizontalPadding ? 0 : 7));
            assert(textItem->x() == paddingStyle.value("paddingLeft").toInt());
            assert(textItem->y() == paddingStyle.value("paddingTop").toInt());
            assert(tiles[1]->x() - tiles[0]->width() == 5);
        }
        streamer->setStyle(appearance);
        for (int alignment = 0; alignment < 5; ++alignment) {
            appearance["alignment"] = alignment;
            streamer->setStyle(appearance);
            assert(styledLabel->property("horizontalAlignment").toInt() == (alignment == 0 ? Qt::AlignHCenter
                : alignment == 2 || alignment == 4 ? Qt::AlignRight : Qt::AlignLeft));
            assert(styledLabel->property("verticalAlignment").toInt() == (alignment == 0 ? Qt::AlignVCenter
                : alignment >= 3 ? Qt::AlignBottom : Qt::AlignTop));
        }
        assert(qAbs(window->width() - queue->x() - queue->width() - 30) < 1);
        assert(qAbs(window->height() - queue->y() - queue->height() - 40) < 1);
        window->resize(1050, 800);
        QTest::qWait(50);
        assert(qAbs(window->width() - queue->x() - queue->width() - 30) < 1);
        assert(qAbs(window->height() - queue->y() - queue->height() - 40) < 1);
        streamer->setSpawnDirection(3);
        assert(tiles[1]->x() == 0 && tiles[0]->x() == tiles[1]->width() + 5);
        appearance["horizontalAnchor"] = 0; appearance["verticalAnchor"] = 0;
        appearance["blur"] = 24; appearance["transparency"] = 65;
        streamer->setStyle(appearance);
        assert(queue->x() == 30 && queue->y() == 40);
        window->resize(1150, 900);
        QTest::qWait(50);
        assert(queue->x() == 30 && queue->y() == 40);
        auto *blur = tiles[0]->findChild<QObject *>("streamerBackgroundBlur");
        assert(blur && blur->property("visible").toBool() && blur->property("blur").toDouble() == 0.75);
        if (const auto screenshot = qEnvironmentVariable("RESKETCH_STREAMER_STYLE_SCREENSHOT"); !screenshot.isEmpty()) {
            QTest::qWait(100);
            assert(window->grabWindow().save(screenshot));
        }
        assert(QMetaObject::invokeMethod(detach, "clicked"));
        assert(queue->window() == separate && queue->x() == 48 && queue->y() == 64);
        const auto keyBounds = [&](QQuickItem *tile) {
            return tile->mapRectToItem(qobject_cast<QQuickWindow *>(separate)->contentItem(), QRectF(0, 0, tile->width(), tile->height()));
        };
        const auto checkKeyBlur = [&] {
            assert(QMetaObject::invokeMethod(separate, "updateBlur"));
            assert(requestedBlurEnabled);
            for (auto *tile : tiles) {
                const auto bounds = keyBounds(tile);
                assert(requestedBlurRegion.contains(bounds.center().toPoint()));
                assert(!requestedBlurRegion.contains(bounds.topLeft().toPoint()));
            }
            const auto left = keyBounds(tiles[1]), right = keyBounds(tiles[0]);
            const QPoint gap(qRound((left.right() + right.left()) / 2), qRound(left.center().y()));
            assert(!requestedBlurRegion.contains(gap));
        };
        checkKeyBlur();
        const auto beforePop = keyBounds(tiles[0]);
        tiles[0]->setScale(0.88);
        checkKeyBlur();
        assert(!requestedBlurRegion.contains(QPoint(qRound(beforePop.left() + 1), qRound(beforePop.center().y()))));
        tiles[0]->setScale(1);
        const auto oldX = tiles[0]->x();
        tiles[0]->setX(oldX + 20);
        checkKeyBlur();
        assert(!requestedBlurRegion.contains(QPoint(qRound(beforePop.left() + 1), qRound(beforePop.center().y()))));
        tiles[0]->setX(oldX);
        separate->resize(200, 100);
        QTest::qWait(30);
        assert(QMetaObject::invokeMethod(separate, "updateBlur"));
        assert(queue->clip());
        const QRegion queueClip(QRectF(queue->x(), queue->y(), queue->width(), queue->height()).toAlignedRect());
        assert((requestedBlurRegion - queueClip).isEmpty());
        separate->resize(500, 400);
        QTest::qWait(50);
        assert(queue->x() == 48 && queue->y() == 64);
        checkKeyBlur();
        assert(separate->close());
        assert(!requestedBlurEnabled && requestedBlurRegion.isEmpty());
        appearance["horizontalAnchor"] = 2; appearance["verticalAnchor"] = 2;
        appearance["offsetX"] = -17; appearance["offsetY"] = 23;
        streamer->setStyle(appearance);
        assert(qAbs(queue->x() + queue->width() / 2 - window->width() / 2 + 17) < 1);
        assert(qAbs(queue->y() + queue->height() / 2 - window->height() / 2 - 23) < 1);
        window->resize(900, 720);
        QTest::qWait(50);
        assert(qAbs(queue->x() + queue->width() / 2 - window->width() / 2 + 17) < 1);
        assert(qAbs(queue->y() + queue->height() / 2 - window->height() / 2 - 23) < 1);
        assert(QMetaObject::invokeMethod(detach, "clicked"));
        separate->resize(600, 400);
        QTest::qWait(50);
        assert(qAbs(queue->x() + queue->width() / 2 - separate->width() / 2 + 17) < 1);
        assert(qAbs(queue->y() + queue->height() / 2 - separate->height() / 2 - 23) < 1);
        assert(separate->close());
        window->resize(200, 140);
        for (int i = 0; i < 7; ++i) QTest::keyClick(window, Qt::Key_I);
        assert(queue->width() <= 200 && queue->x() >= 0 && queue->x() + queue->width() <= window->width());
        assert(restored.streamer()->style() == streamer->style() && restored.streamer()->spawnDirection() == 3);
        appearance["fontSize"] = 999; appearance["paddingLeft"] = -10;
        appearance["radius"] = "invalid"; appearance["background"] = "invalid";
        streamer->setStyle(appearance);
        assert(streamer->style().value("fontSize").toInt() == 96 && streamer->style().value("paddingLeft").toInt() == 0);
        assert(streamer->style().value("radius").toInt() == 8 && streamer->style().value("background").toString() == "#20232a");
        streamer->setEnabled(false);
        settings.setReduceMotion(false);
        QQmlComponent settingsComponent(&engine, QUrl::fromLocalFile(QDir::current().absoluteFilePath("src/SettingsWindow.qml")));
        std::unique_ptr<QObject> settingsPage(settingsComponent.create());
        assert(settingsPage);
        checkSettingsNavigation(qobject_cast<QQuickWindow *>(settingsPage.get()), settings);
        assert(settingsPage->property("selectedSection").toInt() == 0);
        assert(settingsPage->findChild<QObject *>("settingsHomeVersion"));
        assert(settingsPage->findChild<QObject *>("settingsGitHubButton"));
        settingsPage->setProperty("selectedSection", 6);
        QList<QQuickItem *> shortcutFrames;
        const auto collectFrames = [&](auto &&self, QQuickItem *item) -> void {
            if (item->objectName().startsWith("shortcutCategory-")) shortcutFrames << item;
            for (auto *child : item->childItems()) self(self, child);
        };
        collectFrames(collectFrames, qobject_cast<QQuickWindow *>(settingsPage.get())->contentItem());
        assert(shortcutFrames.size() == 4);
        for (auto *frame : shortcutFrames) assert(frame->property("padding").toInt() > 0);
        settingsPage->setProperty("selectedSection", 7);
        assert(settingsPage->findChild<QObject *>("streamerDurationSlider")->property("visible").toBool());
        // Reproduce the desktop SpinBox text editor replacing its value binding.
        for (const auto *field : {"offsetX", "offsetY", "marginX", "marginY", "paddingTop", "paddingRight",
                                 "paddingBottom", "paddingLeft", "minWidth",
                                 "minHeight", "fontSize", "radius", "transparency", "blur", "shadowStrength"}) {
            auto *spin = settingsPage->findChild<QObject *>(QStringLiteral("streamerStyle-") + field);
            auto *slider = settingsPage->findChild<QObject *>(QStringLiteral("streamerStyleSlider-") + field);
            assert(spin && slider);
            auto *editor = spin->property("contentItem").value<QObject *>();
            editor->setProperty("text", QString::number(spin->property("from").toInt()));
            assert(QMetaObject::invokeMethod(editor, "textEdited"));
            const int expected = qMin(37, spin->property("to").toInt());
            slider->setProperty("value", expected);
            assert(QMetaObject::invokeMethod(slider, "moved"));
            assert(streamer->style().value(field).toInt() == expected);
            assert(spin->property("value").toInt() == expected);
            assert(editor->property("text").toString() == spin->property("displayText").toString());
        }
        for (const auto *axis : {"X", "Y"}) {
            auto *spin = settingsPage->findChild<QObject *>(QStringLiteral("streamer") + axis + "Position");
            auto *slider = settingsPage->findChild<QObject *>(QStringLiteral("streamer") + axis + "Slider");
            auto *editor = spin->property("contentItem").value<QObject *>();
            editor->setProperty("text", "0");
            assert(QMetaObject::invokeMethod(editor, "textEdited"));
            slider->setProperty("value", 63);
            assert(QMetaObject::invokeMethod(slider, "moved"));
            assert(spin->property("value").toInt() == 63 && editor->property("text").toString() == "63");
        }
        auto *preview = settingsPage->findChild<QQuickItem *>("streamerSettingsPreview");
        assert(preview && preview->property("entryCount").toInt() == 1 && preview->isVisible());
        QQuickItem *previewLabel = nullptr;
        const auto findPreviewLabel = [&](auto &&self, QQuickItem *item) -> void {
            if (item->objectName() == "streamerKeyLabel") previewLabel = item;
            for (auto *child : item->childItems()) self(self, child);
        };
        findPreviewLabel(findPreviewLabel, preview);
        assert(previewLabel && previewLabel->property("text").toString() == "Ctrl + K");
        auto previewStyle = streamer->style();
        previewStyle["fontSize"] = 26; previewStyle["textColor"] = "#ab1234";
        streamer->setStyle(previewStyle);
        assert(previewLabel->property("font").value<QFont>().pixelSize() == 26);
        assert(previewLabel->property("color").value<QColor>() == QColor("#ab1234"));
        QTest::qWait(550);
        assert(preview->property("entryCount").toInt() == 1);
        auto *paddingControl = settingsPage->findChild<QObject *>("streamerStyle-paddingLeft");
        assert(paddingControl);
        paddingControl->setProperty("value", 16);
        assert(QMetaObject::invokeMethod(paddingControl, "valueModified"));
        assert(streamer->style().value("paddingLeft").toInt() == 16);
        auto *stickyControl = settingsPage->findChild<QObject *>("streamerStickyPosition");
        assert(stickyControl && stickyControl->property("checked").toBool());
        auto *windowMargins = settingsPage->findChild<QObject *>("streamerStyleRow-marginX");
        assert(windowMargins && !windowMargins->property("visible").toBool());
        settingsPage->setProperty("streamerOverlay", QVariant::fromValue(overlay));
        auto *windowWidth = settingsPage->findChild<QObject *>("streamerStyle-windowWidth");
        auto *windowHeight = settingsPage->findChild<QObject *>("streamerStyle-windowHeight");
        assert(windowWidth && windowHeight && windowWidth->property("visible").toBool());
        windowWidth->setProperty("value", 720);
        assert(QMetaObject::invokeMethod(windowWidth, "valueModified"));
        windowHeight->setProperty("value", 360);
        assert(QMetaObject::invokeMethod(windowHeight, "valueModified"));
        assert(restored.streamer()->style().value("windowWidth").toInt() == 720
            && restored.streamer()->style().value("windowHeight").toInt() == 360);
        overlay->setProperty("detached", true);
        assert(separate->size() == QSize(720, 360));
        assert(windowMargins->property("visible").toBool());
        overlay->setProperty("detached", false);
        assert(!windowMargins->property("visible").toBool());
        for (const auto *field : {"paddingTop", "paddingRight", "paddingBottom", "paddingLeft"}) {
            auto *control = settingsPage->findChild<QObject *>(QStringLiteral("streamerStyle-") + field);
            assert(control);
            control->setProperty("value", 11);
            assert(QMetaObject::invokeMethod(control, "valueModified"));
            assert(streamer->style().value(field).toInt() == 11);
        }
        auto *horizontalAnchor = settingsPage->findChild<QObject *>("streamerHorizontalAnchor");
        auto *verticalAnchor = settingsPage->findChild<QObject *>("streamerVerticalAnchor");
        assert(horizontalAnchor->property("count").toInt() == 3 && verticalAnchor->property("count").toInt() == 3);
        auto *maximumControl = settingsPage->findChild<QObject *>("streamerMaximumEntriesValue");
        auto *maximumSlider = settingsPage->findChild<QObject *>("streamerMaximumEntriesSlider");
        assert(maximumControl && maximumSlider);
        auto *maximumEditor = maximumControl->property("contentItem").value<QObject *>();
        maximumEditor->setProperty("text", "2");
        assert(QMetaObject::invokeMethod(maximumEditor, "textEdited"));
        maximumSlider->setProperty("value", 7);
        assert(QMetaObject::invokeMethod(maximumSlider, "moved"));
        assert(maximumControl->property("value").toInt() == 7);
        assert(maximumEditor->property("text").toString() == "7");
        maximumControl->setProperty("value", 10);
        assert(QMetaObject::invokeMethod(maximumControl, "valueModified"));
        streamer->setEnabled(true);
        for (int i = 0; i < 12; ++i) streamer->pressed(window, QString::number(i), false);
        assert(count() == 10 && labels().first() == "2" && labels().last() == "11");
        maximumControl->setProperty("value", 3);
        assert(QMetaObject::invokeMethod(maximumControl, "valueModified"));
        assert(count() == 3 && labels() == (QStringList{"9", "10", "11"}));
        maximumSlider->setProperty("value", 1);
        assert(QMetaObject::invokeMethod(maximumSlider, "moved"));
        assert(count() == 1 && labels().last() == "11");
        streamer->pressed(window, QStringLiteral("Ctrl"), false);
        streamer->scrolled(window, 1, QStringLiteral("Ctrl"), true);
        streamer->scrolled(window, 1, QStringLiteral("Ctrl"), false);
        assert(count() == 1 && labels().last() == "Ctrl + Scroll: +2");
        assert(restored.streamer()->maximumEntries() == 1);
        streamer->setMaximumEntries(0);
        assert(streamer->maximumEntries() == 1);
        streamer->setMaximumEntries(99);
        assert(streamer->maximumEntries() == 32);
        const auto sections = settingsPage->property("sections").value<QJSValue>().toVariant().toList();
        assert(sections[7].toMap().value("title") == "Streamer" && sections[8].toMap().value("title") == "Updates");
        streamer->setEnabled(true);
        QTest::keyClick(window, Qt::Key_D);
        settings.resetSettings();
        assert(!streamer->enabled() && count() == 0 && !overlay->property("visible").toBool());
        assert(streamer->xPosition() == 2 && streamer->yPosition() == 95);
        assert(streamer->durationMs() == 2000 && durationSlider->property("value").toInt() == 2000);
        assert(streamer->maximumEntries() == 8 && maximumControl->property("value").toInt() == 8);
        assert(!streamer->spawnUpwards() && direction->property("currentIndex").toInt() == 0);
        assert(streamer->style().value("fontSize").toInt() == 14 && !streamer->style().value("sticky").toBool());
        assert(streamer->style().value("windowWidth").toInt() == 384 && streamer->style().value("windowHeight").toInt() == 328);
        assert(windowWidth->property("value").toInt() == 384 && windowHeight->property("value").toInt() == 328);
        assert(window->findChild<QObject *>("streamerXPosition")->property("value").toInt() == 2);
        puts("Streamer: input, timers, directions, styling, edited-number/slider synchronization, live preview, settings navigation, shortcut frames, persistence and reset passed");
        return 0;
    }
    if (app.arguments().contains(QStringLiteral("--updates"))) {
        checkUpdates();
        return 0;
    }
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
        AppSettings colors;
        assert(colors.useSystemColors());
        assert(KColorSchemeManager::instance()->activeSchemeId().isEmpty());
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("appSettings", &colors);
        engine.load(QUrl::fromLocalFile(QDir::current().absoluteFilePath("src/SettingsWindow.qml")));
        assert(!engine.rootObjects().isEmpty());
        auto *window = engine.rootObjects().first();
        window->setProperty("selectedSection", 7);
        assert(window->findChild<QObject *>("streamerModeToggle")->property("visible").toBool());
        const auto sections = window->property("sections").value<QJSValue>().toVariant().toList();
        assert(sections[7].toMap().value("title") == "Streamer" && sections[8].toMap().value("title") == "Updates");
        window->setProperty("selectedSection", 1);
        auto *systemCheck = window->findChild<QObject *>("useSystemColorsCheck");
        auto *combo = window->findChild<QObject *>("appThemeCombo");
        assert(systemCheck && combo);
        assert(systemCheck->property("checked").toBool() && !combo->property("enabled").toBool());
        assert(QMetaObject::invokeMethod(systemCheck, "toggle"));
        assert(QMetaObject::invokeMethod(systemCheck, "toggled"));
        QCoreApplication::processEvents();
        assert(!colors.useSystemColors() && combo->property("enabled").toBool());
        const auto checkScheme = [&](const QString &id) {
            QCoreApplication::processEvents();
            assert(KColorSchemeManager::instance()->activeSchemeId() == id);
            const QSettings scheme(QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                QStringLiteral("color-schemes/") + id + QStringLiteral(".colors")), QSettings::IniFormat);
            const auto rgb = scheme.value(QStringLiteral("Colors:Window/BackgroundNormal")).toStringList();
            assert(rgb.size() == 3);
            const QColor expected(rgb[0].toInt(), rgb[1].toInt(), rgb[2].toInt());
            assert(QGuiApplication::palette().color(QPalette::Window) == expected);
            assert(window->property("color").value<QColor>() == expected);
            assert(colors.figmaPalette().value("window").toString() == expected.name());
        };
        colors.setTheme(QStringLiteral("dark"));
        checkScheme(QStringLiteral("BreezeDark"));
        assert(colors.darkTheme() && combo->property("currentIndex").toInt() == 1);
        {
            AppSettings restored;
            assert(!restored.useSystemColors() && restored.theme() == QStringLiteral("dark"));
            checkScheme(QStringLiteral("BreezeDark"));
        }
        colors.setTheme(QStringLiteral("light"));
        checkScheme(QStringLiteral("BreezeLight"));
        assert(!colors.darkTheme() && combo->property("currentIndex").toInt() == 0);
        colors.setTheme(QStringLiteral("auto")); // The menu's system action uses the same toggle.
        QCoreApplication::processEvents();
        assert(colors.useSystemColors() && !combo->property("enabled").toBool());
        assert(KColorSchemeManager::instance()->activeSchemeId().isEmpty());
        assert(!QGuiApplication::instance()->property("KDE_COLOR_SCHEME_PATH").toString().contains("BreezeLight.colors"));
        colors.setUseSystemColors(false);
        checkScheme(QStringLiteral("BreezeLight")); // Retains the last manual choice.
        colors.setUseSystemColors(true);
        puts("System color default, Breeze palettes, live settings controls and theme persistence checks passed");
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
    assert(settings.smoothScrolling() && settings.inertialScrolling());
    assert(settings.gestureSensitivity() == 100 && settings.mouseScrollSensitivity() == 100 && settings.hideSidebarScrollbars());
    settings.setGestureSensitivity(200);
    settings.setMouseScrollSensitivity(150);
    settings.setHideSidebarScrollbars(false);
    { AppSettings saved; assert(saved.gestureSensitivity() == 200 && saved.mouseScrollSensitivity() == 150 && !saved.hideSidebarScrollbars()); }
    settings.setGestureSensitivity(900);
    settings.setMouseScrollSensitivity(900);
    assert(settings.mouseScrollSensitivity() == 500);
    { AppSettings saved; assert(saved.mouseScrollSensitivity() == 500); }
    settings.setMouseScrollSensitivity(-10);
    assert(settings.gestureSensitivity() == 300 && settings.mouseScrollSensitivity() == 25);
    settings.resetSettings();
    assert(settings.gestureSensitivity() == 100 && settings.mouseScrollSensitivity() == 100 && settings.hideSidebarScrollbars());
    settings.setSmoothScrolling(false);
    settings.setInertialScrolling(false);
    { AppSettings saved; assert(!saved.smoothScrolling() && !saved.inertialScrolling()); }
    settings.resetSettings();
    assert(settings.smoothScrolling() && settings.inertialScrolling());
    settings.updates()->setEnabled(false); // Update checks use their own local HTTP fixture.
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
        assert(requestedBlurRegion.isEmpty()); // The platform controls fullscreen geometry.
        settings.setFloatingSidebars(true);
        settings.refreshWindowBlur(&window);
        assert(requestedBlurRegion.isEmpty()); // Home does not float.
        window.setProperty("floatingFileSidebars", true);
        settings.refreshWindowBlur(&window);
        assert(requestedBlurEnabled && requestedBlurRegion.isEmpty()); // Floating sidebars reveal the desktop.
        settings.setSidebarBackdrop(QStringLiteral("canvas"));
        settings.refreshWindowBlur(&window);
        assert(requestedBlurEnabled && requestedBlurRegion.isEmpty()); // Loading screens retain desktop blur.
        settings.setSidebarBackdrop(QStringLiteral("desktop"));
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
    puts("Fullscreen, resized windows, canvas-mode loaders and desktop blur disable checks passed");
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
    settings.setWindowControlsInTabBar(true);
    evaluate("destination.homeView.stop(); destination.homeView.loadHtml('<html><body><input autofocus></body></html>'); destination.activateHome(false);");
    render();
    auto *maximize = destination->findChild<QQuickItem *>("maximizeWindowButton");
    assert(maximize);
    destination->showNormal();
    destination->requestActivate();
    auto *home = qobject_cast<QQuickItem *>(evaluate("destination.homeView").toQObject());
    home->forceActiveFocus();
    for (int click = 0; click < 2; ++click) {
        const auto point = maximize->mapToScene(QPointF(maximize->width() / 2, maximize->height() / 2)).toPoint();
        QTest::mouseClick(destination, Qt::LeftButton, Qt::NoModifier, point);
        render();
        const auto visibility = destination->visibility();
        assert(visibility == (click == 0 ? QWindow::Maximized : QWindow::Windowed));
        assert(home->hasActiveFocus() && !maximize->hasActiveFocus());
        QTest::keyClick(destination, Qt::Key_Space);
        assert(destination->visibility() == visibility);
    }
    // Deliberately reaching the control by keyboard must still allow activation.
    maximize->forceActiveFocus(Qt::TabFocusReason);
    QTest::keyClick(destination, Qt::Key_Space);
    assert(destination->visibility() == QWindow::Maximized);
    destination->showNormal();
    home->forceActiveFocus();
    puts("Home Space: mouse maximize/restore preserves web focus; keyboard window controls remain accessible");
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
    CefTaskMonitor taskMonitor;
    taskMonitor.setActive(true);
    auto *taskView = qobject_cast<CefQuickView *>(evaluate("destination.homeView").toQObject());
    QVariantMap resource;
    for (int attempt = 0; attempt < 50; ++attempt) {
        resource = taskMonitor.resourceUsage(taskView);
        if (resource.value("memory").toDouble() > 0 && resource.value("cpu").isValid()) break;
        render();
    }
    assert(resource.value("taskId").toLongLong() >= 0);
    assert(resource.value("memory").toDouble() > 0 && resource.value("cpu").isValid()
           && resource.value("cpu").toDouble() >= 0);
    taskMonitor.setActive(false);
    assert(taskMonitor.resourceUsage(taskView).isEmpty());
    puts("Tab task manager measures Chromium's live browser tasks without renderer-local PIDs");
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
    settings.setReduceMotion(false);
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
    const double wheelStart = position(overview, "contentY");
    wheel(overview, {}, QPoint(0, -120), Qt::NoScrollPhase, false, QPointingDevice::primaryPointingDevice());
    assert(overview->property("smoothWheel").toBool()); // Mouse wheel retains its easing.
    const double wheelTarget = position(overview, "wheelTargetY");
    assert(wheelTarget > wheelStart);
    assert(qAbs(position(overview, "contentY") - wheelStart) < 1);
    render();
    assert(position(overview, "contentY") > wheelStart && position(overview, "contentY") < wheelTarget);
    // Reversing a wheel burst responds immediately and keeps an eased target.
    wheel(overview, {}, QPoint(0, 120), Qt::NoScrollPhase, false, QPointingDevice::primaryPointingDevice());
    assert(qAbs(position(overview, "wheelTargetY") - wheelStart) < 1);
    wheel(overview, {}, {}, Qt::ScrollBegin);
    assert(!overview->property("smoothWheel").toBool()); // A new gesture stops old mouse-wheel easing.
    wheel(overview, {}, {}, Qt::ScrollEnd);
    puts("Native trackpad axes, pixels, momentum, natural scrolling, and mouse-wheel easing checks passed");
    auto *uiScroll = overview->findChild<QQuickItem *>("scrollGestureArea");
    assert(uiScroll);
    const auto uiWheel = [&](QPoint pixels, QPoint angles, Qt::ScrollPhase phase, bool inverted = false,
                              const QPointingDevice *device = nullptr) {
        QWheelEvent event(QPointF(80,200), QPointF(80,200), pixels, angles, Qt::NoButton, Qt::NoModifier,
                          phase, inverted, Qt::MouseEventSynthesizedBySystem, device ? device : &touchpad);
        QCoreApplication::sendEvent(uiScroll, &event);
    };
    settings.setSmoothScrolling(false);
    settings.setInertialScrolling(false);
    assert(evaluate("destination.views.every(v=>!v.settings.scrollAnimatorEnabled && !v.settings.inertialScrollingEnabled)").toBool());
    overview->setProperty("contentY", 100.0);
    uiWheel({}, QPoint(0,-120), Qt::NoScrollPhase, false, QPointingDevice::primaryPointingDevice());
    assert(!overview->property("smoothWheel").toBool());
    assert(position(overview,"contentY") > 100);
    overview->setProperty("contentY", 100.0);
    settings.setMouseScrollSensitivity(200);
    uiWheel({}, QPoint(0,-120), Qt::NoScrollPhase, false, QPointingDevice::primaryPointingDevice());
    const double fasterMouseTarget = 100 + uiScroll->property("wheelStep").toDouble() * 2;
    assert(qAbs(position(overview,"contentY") - fasterMouseTarget) < 1);
    uiWheel(QPoint(0,-12), {}, Qt::ScrollUpdate);
    assert(qAbs(position(overview,"contentY") - fasterMouseTarget - 24) < 1); // Precision scrolling uses the same speed setting.
    uiWheel(QPoint(0,-12), {}, Qt::NoScrollPhase, false, QPointingDevice::primaryPointingDevice());
    assert(qAbs(position(overview,"contentY") - fasterMouseTarget - 48) < 1);
    overview->setProperty("contentY", 100.0);
    uiWheel({}, {}, Qt::ScrollBegin, false, QPointingDevice::primaryPointingDevice());
    uiWheel({}, QPoint(0,-120), Qt::ScrollUpdate, false, QPointingDevice::primaryPointingDevice());
    assert(qAbs(position(overview,"contentY") - fasterMouseTarget) < 1);
    settings.setMouseScrollSensitivity(100);
    uiWheel({}, {}, Qt::ScrollBegin);
    for(int i=0;i<3;++i) { uiWheel(QPoint(0,-12), {}, Qt::ScrollUpdate); render(); }
    uiWheel({}, {}, Qt::ScrollEnd);
    const double noInertia = position(overview,"contentY");
    render();
    assert(qAbs(position(overview,"contentY") - noInertia) < 1);
    uiWheel({}, {}, Qt::ScrollBegin);
    uiWheel(QPoint(0,-24), {}, Qt::ScrollMomentum);
    uiWheel({}, {}, Qt::ScrollEnd);
    assert(qAbs(position(overview,"contentY") - noInertia) < 1);
    settings.setInertialScrolling(true);
    overview->setProperty("contentY", 0.0);
    uiWheel({}, {}, Qt::ScrollBegin);
    for(int i=0;i<3;++i) { uiWheel(QPoint(0,-24), {}, Qt::ScrollUpdate); if(i<2) render(); }
    uiWheel({}, {}, Qt::ScrollEnd);
    const double beforeInertia = position(overview,"contentY");
    render();
    assert(position(overview,"contentY") > beforeInertia);
    settings.setSmoothScrolling(true);
    uiWheel({}, {}, Qt::ScrollBegin);
    uiWheel({}, {}, Qt::ScrollEnd);
    puts("Scroll preference persistence, live web/UI updates and native UI inertia checks passed");
    evaluate("destination.dismissOverview(); destination.activateTab(0, false); var pinchFixtureReady = false;"
             "destination.activeView.runJavaScript(\"document.body.innerHTML='<style>body{margin:0}nav{position:absolute;left:0;top:0;width:200px;height:100vh;background:gray;z-index:1}.gpu-view-content{position:absolute;inset:0}</style><div class=gpu-view-content></div><nav data-onboarding-key=unified-design-onboarding-left-panel></nav>';window.zoomWheels=[];addEventListener('wheel',e=>{e.preventDefault();zoomWheels.push(e.deltaY)},{passive:false})\", () => pinchFixtureReady = true);");
    for (int i = 0; i < 50 && !evaluate("pinchFixtureReady").toBool(); ++i) render();
    assert(evaluate("pinchFixtureReady").toBool());
    evaluate("destination.activeView.restoreHistoryUrl('https://www.figma.com/design/PinchFixture/Test'); destination.activeView.hasLoadedFrame = true;");
    render();
    const auto nativePinch = [&](Qt::NativeGestureType type, double value = 0, QPointF delta = {}, QPointF position = QPointF(80, 300)) {
        auto *content = qobject_cast<QQuickItem *>(destination->property("browserContent").value<QObject *>());
        assert(content);
        const auto scene = content->mapToScene(position);
        QNativeGestureEvent event(type, &touchpad, 2, scene, scene, destination->mapToGlobal(scene), value, delta);
        QCoreApplication::sendEvent(destination, &event);
    };
    nativePinch(Qt::BeginNativeGesture);
    nativePinch(Qt::ZoomNativeGesture, -0.1);
    render();
    assert(evaluate("destination.overviewPinchTracking && destination.overviewPinchAccepted && destination.overviewVisible").toBool());
    const double pinchProgress = destination->property("overviewProgress").toDouble();
    assert(pinchProgress > 0 && pinchProgress < 0.5);
    settings.setGestureSensitivity(200);
    evaluate("destination.updateOverviewPinch(destination.overviewPinchScale, destination.overviewPinchTranslation)");
    assert(destination->property("overviewProgress").toDouble() > pinchProgress * 1.5);
    settings.setGestureSensitivity(100);
    evaluate("destination.updateOverviewPinch(destination.overviewPinchScale, destination.overviewPinchTranslation)");
    const double pinchX = destination->property("overviewPinchOffsetX").toDouble();
    nativePinch(Qt::PanNativeGesture, 0, QPointF(30, 15));
    render();
    assert(qAbs(destination->property("overviewPinchOffsetX").toDouble() - pinchX - 30) < 1);
    assert(qAbs(destination->property("overviewProgress").toDouble() - pinchProgress) < 0.001);
    nativePinch(Qt::ZoomNativeGesture, -0.5);
    const double releasedProgress = destination->property("overviewProgress").toDouble();
    const double releasedScale = destination->property("overviewPinchScale").toDouble();
    nativePinch(Qt::EndNativeGesture);
    for (int i = 0; i < 30 && destination->property("overviewProgress").toDouble() < 0.999; ++i) render();
    if(destination->property("overviewProgress").toDouble()!=1 || !destination->property("overviewVisible").toBool())
        fprintf(stderr,"pinch failure: releaseScale=%f releaseProgress=%f finalProgress=%f closing=%d tracking=%d visible=%d animation=%d\n", releasedScale,releasedProgress,
            destination->property("overviewProgress").toDouble(),destination->property("overviewClosing").toBool(),destination->property("overviewPinchTracking").toBool(),destination->property("overviewVisible").toBool(),destination->property("overviewAnimationRunning").toBool());
    assert(destination->property("overviewProgress").toDouble() == 1 && destination->property("overviewVisible").toBool());
    assert(!destination->property("overviewPinchTracking").toBool());
    evaluate(QString("var card = destination.overviewNavigationCards().find(c=>c.target===destination.activeView);"
             "destination.beginOverviewPinch(Qt.point(card.x+destination.overviewCardWidth/2,"
             "card.y+destination.overviewCardHeight/2-%1));").arg(position(overview, "contentY")));
    assert(destination->property("overviewPinchOpeningCard").toBool());
    evaluate("destination.updateOverviewPinch(3, Qt.point(0,0))");
    const double stretch3 = destination->property("overviewPinchStretch").toDouble();
    assert(stretch3 > 1 && stretch3 < 2);
    evaluate("destination.updateOverviewPinch(4, Qt.point(0,0))");
    const double stretch4 = destination->property("overviewPinchStretch").toDouble();
    evaluate("destination.updateOverviewPinch(5, Qt.point(0,0))");
    const double stretch5 = destination->property("overviewPinchStretch").toDouble();
    assert(stretch5 > stretch4 && stretch4 > stretch3 && stretch5 - stretch4 < stretch4 - stretch3);
    evaluate("destination.updateOverviewPinch(10000, Qt.point(0,0))");
    assert(destination->property("overviewPinchStretch").toDouble() > stretch5); // No hard upper scale cap.
    evaluate("destination.updateOverviewPinch(3, Qt.point(0,0)); destination.finishOverviewPinch()");
    for (int i = 0; i < 30 && destination->property("overviewVisible").toBool(); ++i) render();
    assert(!destination->property("overviewVisible").toBool());
    assert(destination->property("overviewPinchStretch").toDouble() == 1);
    evaluate("destination.dismissOverview();");
    nativePinch(Qt::BeginNativeGesture);
    nativePinch(Qt::ZoomNativeGesture, -0.25);
    render();
    nativePinch(Qt::ZoomNativeGesture, 0.3);
    nativePinch(Qt::EndNativeGesture);
    for (int i = 0; i < 10 && destination->property("overviewVisible").toBool(); ++i) render();
    assert(!destination->property("overviewVisible").toBool());
    nativePinch(Qt::BeginNativeGesture, 0, {}, QPointF(400, 300));
    nativePinch(Qt::ZoomNativeGesture, -0.5, {}, QPointF(400, 300));
    render();
    nativePinch(Qt::EndNativeGesture, 0, {}, QPointF(400, 300));
    assert(!destination->property("overviewVisible").toBool());
    puts("Native sidebar pinch, pan, completion and reversal checks passed");
    evaluate("destination.activeView.runJavaScript('zoomWheels=[]')");
    render();
    nativePinch(Qt::BeginNativeGesture, 0, {}, QPointF(400,300));
    nativePinch(Qt::ZoomNativeGesture, 0.2, {}, QPointF(400,300));
    render();
    assert(evaluate("destination.canvasPinchView === destination.activeView").toBool());
    nativePinch(Qt::EndNativeGesture, 0, {}, QPointF(400,300));
    evaluate("var zoomResult=[]");
    for (int i=0; i<20 && !evaluate("zoomResult.some(delta=>delta<0)").toBool(); ++i) {
        evaluate("destination.activeView.runJavaScript('zoomWheels',result=>zoomResult=result)");
        render();
    }
    assert(evaluate("zoomResult.some(delta=>delta<0)").toBool());
    // Deliver real Qt wheel events through the CEF item and its QML acceptance signal.
    auto *swipeView = qobject_cast<QQuickItem *>(destination->property("activeView").value<QObject *>());
    assert(swipeView);
    const auto sidebarWheel = [&](QPoint pixels, Qt::ScrollPhase phase) {
        const QPointF local(80,300);
        auto *browser = qobject_cast<QQuickItem *>(destination->property("browserContent").value<QObject *>());
        const auto scene = browser->mapToScene(local);
        QWheelEvent event(scene, destination->mapToGlobal(scene), pixels, {}, Qt::NoButton, Qt::NoModifier,
                          phase, false, Qt::MouseEventSynthesizedBySystem, &touchpad);
        QCoreApplication::sendEvent(destination, &event);
    };
    settings.setMouseScrollSensitivity(200);
    sidebarWheel({}, Qt::ScrollBegin);
    render();
    assert(destination->property("sidebarSwipeAllowed").toBool());
    sidebarWheel(QPoint(-100,0), Qt::ScrollUpdate);
    assert(qAbs(swipeView->property("slideX").toDouble() + 100) < 1);
    assert(evaluate("Math.abs(destination.sidebarSwipeTarget.slideX-destination.sidebarSwipeView.slideX)"
        "-destination.browserWidth === destination.tabSlideGap && destination.tabSlideGap>0").toBool());
    render(); // Explicit scroll phases must hold the transition while fingers pause.
    assert(qAbs(swipeView->property("slideX").toDouble() + 100) < 1);
    sidebarWheel(QPoint(-500,0), Qt::ScrollUpdate);
    sidebarWheel({}, Qt::ScrollEnd);
    for(int i=0; i<10 && destination->property("activeView").value<QObject *>() == swipeView; ++i) render();
    assert(destination->property("activeView").value<QObject *>() != swipeView);
    evaluate("var reverseReady=false;destination.activeView.runJavaScript(\"document.body.innerHTML='<div class=toolbelt--root--fixture style=\\\"position:absolute;inset:0\\\"><button style=\\\"width:100%;height:100%\\\">Move</button></div>'\",()=>reverseReady=true)");
    for(int i=0;i<30 && !evaluate("reverseReady").toBool();++i) render();
    assert(evaluate("reverseReady").toBool());
    evaluate("destination.activeView.restoreHistoryUrl('https://www.figma.com/design/ReverseFixture/Test');destination.activeView.hasLoadedFrame=true");
    sidebarWheel({}, Qt::ScrollBegin);
    render();
    assert(destination->property("sidebarSwipeAllowed").toBool());
    sidebarWheel(QPoint(100,0), Qt::ScrollUpdate);
    assert(evaluate("Math.abs(destination.sidebarSwipeTarget.slideX-destination.sidebarSwipeView.slideX)"
        "-destination.browserWidth === destination.tabSlideGap").toBool());
    sidebarWheel(QPoint(500,0), Qt::ScrollUpdate);
    sidebarWheel({}, Qt::ScrollEnd);
    for(int i=0;i<10 && destination->property("activeView").value<QObject *>() != swipeView;++i) render();
    assert(destination->property("activeView").value<QObject *>() == swipeView);
    settings.setMouseScrollSensitivity(100);
    evaluate("destination.openOverview(false)");
    for(int i=0; i<10 && destination->property("overviewProgress").toDouble() < 0.999; ++i) render();
    const auto cardPoint = evaluate("var pinchCard=destination.overviewNavigationCards().find(c=>typeof c.target!=='string' && c.target!==destination.activeView);"
        "Qt.point(pinchCard.x+destination.overviewCardWidth/2,pinchCard.y+destination.overviewCardHeight/2)");
    QPointF cardPosition(cardPoint.property("x").toNumber(),cardPoint.property("y").toNumber());
    cardPosition.ry() -= overview->property("contentY").toDouble();
    nativePinch(Qt::BeginNativeGesture, 0, {}, cardPosition);
    nativePinch(Qt::ZoomNativeGesture, 0.2, {}, cardPosition);
    render();
    assert(destination->property("overviewPinchOpeningCard").toBool());
    assert(destination->property("overviewProgress").toDouble() < 1);
    nativePinch(Qt::ZoomNativeGesture, 0.5, {}, cardPosition);
    nativePinch(Qt::EndNativeGesture, 0, {}, cardPosition);
    for(int i=0; i<10 && destination->property("overviewVisible").toBool(); ++i) render();
    assert(!destination->property("overviewVisible").toBool());
    assert(evaluate("destination.activeView === pinchCard.target").toBool());
    puts("Native canvas zoom, sidebar tab swipes and overview card pinch-out checks passed");
}
