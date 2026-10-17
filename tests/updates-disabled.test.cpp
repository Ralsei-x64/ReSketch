// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "UpdateChecker.h"
#include <QApplication>
#include <QEventLoop>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTcpServer>
#include <QTimer>
#include <cassert>
#include <cstdio>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QTemporaryDir temporary;
    assert(temporary.isValid());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, temporary.path());
    QSettings settings(QStringLiteral("aether64"), QStringLiteral("ReSketch"));
    settings.setValue("updates/startup", true);
    settings.setValue("updates/periodic", true);
    settings.setValue("updates/completedVersion", "1.0.0");
    settings.sync();
    QTcpServer server;
    assert(server.listen(QHostAddress::LocalHost));
    int requests = 0;
    QObject::connect(&server, &QTcpServer::newConnection, [&] { ++requests; });
    const QUrl api(QStringLiteral("http://127.0.0.1:%1/").arg(server.serverPort()));
    UpdateChecker updater(nullptr, "1.0.0", api, api);
    assert(updater.managedBySystem());
    for (const char *property : {"enabled", "periodicEnabled", "canInstall", "canMigrate"}) {
        if (updater.metaObject()->indexOfProperty(property) < 0) continue;
        if (QByteArray(property) == "enabled" || QByteArray(property) == "periodicEnabled")
            assert(updater.setProperty(property, true));
        assert(!updater.property(property).toBool());
    }
    for (const char *method : {"checkAtStartup", "checkForUpdates", "migrateToMain", "installUpdate",
                              "skipUpdate", "openRelease", "cancelDownload", "finishUpdate", "dismissCompletedUpdate"}) {
        if (updater.metaObject()->indexOfMethod((QByteArray(method) + "()").constData()) >= 0)
            assert(QMetaObject::invokeMethod(&updater, method));
    }
    assert(updater.available().isEmpty() && !updater.installing() && !updater.installed());
    if (updater.metaObject()->indexOfProperty("completedUpdate") >= 0)
        assert(updater.property("completedUpdate").toMap().isEmpty());
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("testUpdater", &updater);
    engine.loadData(R"(
import QtQuick
import QtQuick.Controls
import "../src" as App
ApplicationWindow {
    visible: true; width: 880; height: 700
    App.UpdateSettings { anchors.fill: parent; updater: testUpdater }
})", QUrl::fromLocalFile(QStringLiteral(RESKETCH_SOURCE_DIR "/tests/disabled-fixture.qml")));
    assert(!engine.rootObjects().isEmpty());
    auto *window = engine.rootObjects().first();
    QEventLoop loop;
    QTimer::singleShot(150, &loop, &QEventLoop::quit);
    loop.exec();
    assert(requests == 0);
    auto *notice = window->findChild<QObject *>("systemManagedUpdatesNotice");
    auto *controls = window->findChild<QObject *>("updateControls");
    assert(notice && controls);
    assert(notice->property("visible").toBool() && notice->property("enabled").toBool());
    assert(notice->property("text") == "Updates managed by system");
    assert(!controls->property("enabled").toBool() && controls->property("opacity").toDouble() == 0.5);
    assert(notice->property("y").toDouble() < controls->property("y").toDouble());
    for (const char *name : {"checkForUpdatesButton", "startupUpdateCheck", "periodicUpdateCheck", "switchToMainButton"}) {
        if (auto *control = window->findChild<QObject *>(QString::fromLatin1(name)))
            assert(!control->property("enabled").toBool());
    }
    settings.sync();
    assert(settings.value("updates/startup").toBool() && settings.value("updates/periodic").toBool());
    assert(settings.value("updates/completedVersion") == "1.0.0");
    const auto prefix = qEnvironmentVariable("RESKETCH_UPDATE_SCREENSHOTS");
    if (!prefix.isEmpty()) assert(qobject_cast<QQuickWindow *>(window)->grabWindow().save(prefix + "-managed.png"));
    puts("System-managed updater: no requests or installation, preferences preserved, notice visible and all controls disabled");
}
