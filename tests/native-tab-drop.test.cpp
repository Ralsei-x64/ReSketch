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
}
