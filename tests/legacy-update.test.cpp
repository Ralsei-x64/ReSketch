// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "UpdateChecker.h"
#include <QApplication>
#include <QDir>
#include <QEventLoop>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <cassert>
#include <cstdio>

void checkMigration()
{
    QTemporaryDir temporary;
    assert(temporary.isValid());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, temporary.path());
    QTcpServer server;
    assert(server.listen(QHostAddress::LocalHost));
    const QUrl api(QStringLiteral("http://127.0.0.1:%1/").arg(server.serverPort()));
    const QString package = "resketch-cef-1.4.15-abcdef0-x86_64.pkg.tar.zst";
    const QByteArray payload(512 * 1024, 'x');
    const auto release = [&](const QString &tag, bool draft = false, bool prerelease = false) {
        return QJsonObject{{"tag_name", tag}, {"draft", draft}, {"prerelease", prerelease},
            {"body", "CEF release notes"}, {"html_url", "javascript:invalid"},
            {"assets", QJsonArray{QJsonObject{{"name", package}}, QJsonObject{{"name", "SHA256SUMS"}}}}};
    };
    QJsonArray releases{release("main-v99.0.0-abcdef0"), release("cef-v9.0.0-abcdef0", true),
        release("cef-v8.0.0-abcdef0", false, true), release("cef-v7.0.0-abcdef0"),
        release("cef-v1.4.15-abcdef0")};
    int requests = 0, pageTwo = 0, httpStatus = 200;
    bool corrupt = false, invalidChecksum = false, paginate = false, malformed = false;
    QObject::connect(&server, &QTcpServer::newConnection, &server, [&] {
        while (auto *socket = server.nextPendingConnection()) {
            QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            QObject::connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                const QByteArray input = socket->property("input").toByteArray() + socket->readAll();
                socket->setProperty("input", input);
                if (!input.contains("\r\n\r\n")) return;
                ++requests;
                QByteArray body;
                if (input.startsWith("GET /downloads/")) {
                    assert(input.contains("/cef-v1.4.15-abcdef0/"));
                    if (input.contains("/SHA256SUMS "))
                        body = (invalidChecksum ? QByteArray("invalid") : QCryptographicHash::hash(payload, QCryptographicHash::Sha256).toHex())
                            + "  " + package.toUtf8() + "\n";
                    else body = corrupt ? QByteArray("corrupt") : payload;
                } else if (malformed) body = "invalid json";
                else if (paginate && !input.contains("page=2 ")) {
                    QJsonArray old;
                    for (int i = 0; i < 100; ++i) old.append(release("main-v99.0.0-abcdef0"));
                    body = QJsonDocument(old).toJson();
                } else {
                    if (input.contains("page=2 ")) ++pageTwo;
                    body = QJsonDocument(releases).toJson();
                }
                socket->write("HTTP/1.1 " + QByteArray::number(httpStatus) + " Test\r\nConnection: close\r\nContent-Length: "
                    + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                socket->disconnectFromHost();
            });
        }
    });
    const QString script = temporary.filePath("installer");
    const QString receipt = temporary.filePath("receipt");
    const auto writeInstaller = [&](int exitCode) {
        QFile file(script);
        assert(file.open(QIODevice::WriteOnly));
        file.write(("#!/bin/sh\ntest -f \"$1\" || exit 9\nprintf '%s\\n' \"$1\" > '" + receipt
            + "'\nexit " + QString::number(exitCode) + "\n").toUtf8());
        file.close();
        assert(file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    };
    writeInstaller(0);
    UpdateChecker updater(nullptr, "0.4.0", api, api.resolved(QUrl("downloads/")));
    assert(!updater.managedBySystem());
    updater.m_installCommand = {script}; // Tests never invoke pacman or authenticate.
    const auto wait = [&] {
        QEventLoop loop;
        QObject::connect(&updater, &UpdateChecker::changed, &loop, [&] { if (!updater.installing()) loop.quit(); });
        QTimer::singleShot(5000, &loop, &QEventLoop::quit);
        if (updater.installing()) loop.exec();
        assert(!updater.installing());
    };
    const auto settle = [] {
        QEventLoop loop;
        QTimer::singleShot(100, &loop, &QEventLoop::quit);
        loop.exec();
    };
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("testUpdater", &updater);
    engine.loadData(R"(
import QtQuick
import QtQuick.Controls
import "../src" as App
ApplicationWindow {
    visible: true; width: 880; height: 700
    App.UpdateSettings { anchors.fill: parent; updater: testUpdater }
    App.UpdateCompleteDialog { id: complete; updater: testUpdater }
    Connections { target: testUpdater; function onInstallationComplete() { complete.open() } }
})", QUrl::fromLocalFile(QStringLiteral(RESKETCH_SOURCE_DIR "/tests/migration-fixture.qml")));
    assert(!engine.rootObjects().isEmpty());
    auto *window = engine.rootObjects().first();
    const auto child = [&](const char *name) {
        auto *item = window->findChild<QObject *>(QString::fromLatin1(name)); assert(item); return item;
    };
    const auto click = [&] { assert(QMetaObject::invokeMethod(child("switchToMainButton"), "clicked")); };
    const auto snapshot = [&](const QString &state) {
        const auto prefix = qEnvironmentVariable("RESKETCH_UPDATE_SCREENSHOTS");
        if (!prefix.isEmpty()) assert(qobject_cast<QQuickWindow *>(window)->grabWindow().save(prefix + "-" + state + ".png"));
    };
    settle();
    assert(requests == 0); // Construction and displaying the Updates page never contact GitHub.
    assert(updater.metaObject()->indexOfMethod("checkAtStartup()") < 0);
    assert(updater.metaObject()->indexOfMethod("checkForUpdates()") < 0);
    assert(updater.metaObject()->indexOfProperty("periodicEnabled") < 0);
    assert(!window->findChild<QObject *>("checkForUpdatesButton"));
    assert(!window->findChild<QObject *>("startupUpdateCheck"));
    assert(!child("systemManagedUpdatesNotice")->property("visible").toBool());
    assert(child("updateControls")->property("enabled").toBool());
    assert(child("legacyBranchHeading")->property("text") == "You're on the Legacy branch.");
    assert(child("switchToMainButton")->property("enabled").toBool());
    snapshot("legacy");
    updater.m_installCommand = {temporary.filePath("missing")};
    updater.changed();
    assert(!child("switchToMainButton")->property("enabled").toBool());
    updater.m_installCommand = {script};
    updater.changed();
    click();
    assert(updater.installing() && !child("switchToMainButton")->property("enabled").toBool());
    assert(child("updateProgressBar")->property("visible").toBool());
    updater.cancelDownload();
    settle();
    assert(!updater.installed() && updater.installError().contains("cancelled") && !QFile::exists(receipt));
    const int afterCancel = requests;
    settle();
    assert(requests == afterCancel); // Cancellation never schedules another lookup.
    httpStatus = 403;
    click(); wait();
    assert(updater.installError().contains("limit") && !QFile::exists(receipt));
    httpStatus = 200; malformed = true;
    click(); wait();
    assert(updater.installError().contains("invalid release list"));
    malformed = false;
    const auto validReleases = releases;
    releases = {release("main-v99.0.0-abcdef0")};
    click(); wait();
    assert(updater.installError().contains("No installable stable version"));
    releases = validReleases;
    corrupt = true;
    const int before = requests;
    click(); updater.migrateToMain(); wait();
    assert(requests == before + 3); // Repeated clicks never start overlapping migrations.
    assert(updater.installError().contains("checksum") && !QFile::exists(receipt));
    assert(updater.available().value("version") == "1.4.15");
    corrupt = false; invalidChecksum = true;
    click(); wait();
    assert(updater.installError().contains("checksum") && !QFile::exists(receipt));
    invalidChecksum = false;
    writeInstaller(126);
    click(); wait();
    assert(updater.installError().contains("cancelled") && !updater.installed());
    QFile::remove(receipt);
    writeInstaller(0);
    paginate = true;
    click(); wait(); settle();
    assert(pageTwo == 1 && updater.installed() && updater.installError().isEmpty());
    assert(QFile::exists(receipt));
    QFile installedPackage(receipt);
    assert(installedPackage.open(QIODevice::ReadOnly));
    assert(!QFile::exists(QString::fromUtf8(installedPackage.readAll()).trimmed()));
    QSettings settings(QStringLiteral("aether64"), QStringLiteral("ReSketch"));
    assert(settings.value("updates/completedVersion") == "1.4.15");
    assert(settings.value("updates/completedChangelog") == "CEF release notes");
    assert(child("switchToMainButton")->property("text") == "Finish Update");
    assert(child("updateCompleteDialog")->property("visible").toBool());
    snapshot("complete");
    QEventLoop closing;
    QObject::connect(child("updateCompleteDialog"), SIGNAL(closed()), &closing, SLOT(quit()));
    QTimer::singleShot(2000, &closing, &QEventLoop::quit);
    assert(QMetaObject::invokeMethod(child("updateLaterButton"), "clicked"));
    if (child("updateCompleteDialog")->property("visible").toBool()) closing.exec();
    assert(!child("updateCompleteDialog")->property("visible").toBool() && updater.installed());
    assert(child("switchToMainButton")->property("enabled").toBool());
    const int installedRequests = requests;
    updater.migrateToMain(); settle();
    assert(requests == installedRequests);
    puts("Legacy stays offline until requested; migration selection, retries, cancellation, checksums, installer outcomes, restart deferral and QML passed");
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    checkMigration();
}
