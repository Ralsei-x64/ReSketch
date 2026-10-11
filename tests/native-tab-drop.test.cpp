// Reuse the app's generated moc; build with tests/check-native-tab-drop.sh.
#define main resketchMain
#include "../src/main.cpp"
#undef main
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QEventLoop>
#include <QMimeData>
#include <QQmlComponent>
#include <QTemporaryDir>
#include <QWheelEvent>
#include <QPointingDevice>
#include <QQuickItem>
#include <cassert>

int main(int argc, char **argv)
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QtWebEngineQuick::initialize();
    QApplication app(argc, argv);
    QTemporaryDir temporary;
    assert(temporary.isValid());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, temporary.path());
    AppSettings settings;
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
