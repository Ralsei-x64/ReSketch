// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "UpdateChecker.h"
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
#include <QDir>
#include <QTemporaryDir>
#include <cassert>
#include <cstdio>

void checkUpdates()
{
    QTcpServer server;
    assert(server.listen(QHostAddress::LocalHost));
    const QUrl api(QStringLiteral("http://127.0.0.1:%1/").arg(server.serverPort()));
    const auto release = [](const QString &tag, bool draft = false) {
        return QJsonObject{{"tag_name", tag}, {"draft", draft}, {"body", "Release notes fallback"},
                           {"html_url", "javascript:invalid"}}; // Never trust a release's external URL.
    };
    QJsonArray releases{release("main-v9.0.0-abcdef0"), release("cef-v1.2.10-abcdef0"),
                        release("cef-v99.0.0-abcdef0", true), release("cef-v1.2.9-abcdef0")};
    const QString changelog = "ReSketch changelog\n\n1.3.0 - 2026-10-16\nNewer changes\n\n"
        "1.2.10 - 2026-10-16\nFirst line\nSecond line\nThird line\nFourth line\n\n"
        "1.2.9 - 2026-10-15\nAlready installed\n";
    int requests = 0, pageTwo = 0, httpStatus = 200;
    bool malformed = false, olderBranch = false, notesFail = false;
    const QByteArray packageData(512 * 1024, 'x');
    const QString packageName = "resketch-cef-1.2.10-abcdef0-x86_64.pkg.tar.zst";
    bool corruptPackage = false, invalidChecksum = false;
    QObject::connect(&server, &QTcpServer::newConnection, &server, [&] {
        while (auto *socket = server.nextPendingConnection()) {
            QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            QObject::connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                const auto input = socket->property("input").toByteArray() + socket->readAll();
                socket->setProperty("input", input);
                if (!input.contains("\r\n\r\n")) return;
                ++requests;
                const bool notes = input.startsWith("GET /contents/");
                const bool secondPage = input.contains("page=2 ");
                if (secondPage) ++pageTwo;
                QByteArray body;
                if (input.startsWith("GET /downloads/") && input.contains("/SHA256SUMS "))
                    body = (invalidChecksum ? QByteArray("invalid") : QCryptographicHash::hash(packageData, QCryptographicHash::Sha256).toHex())
                        + "  " + packageName.toUtf8() + "\n";
                else if (input.startsWith("GET /downloads/")) body = corruptPackage ? QByteArray("corrupted") : packageData;
                else if (notes) body = changelog.toUtf8();
                else if (malformed) body = "not json";
                else if (olderBranch && !secondPage) {
                    QJsonArray page;
                    for (int i = 0; i < 100; ++i) page.append(release("main-v9.0.0-abcdef0"));
                    body = QJsonDocument(page).toJson();
                } else body = QJsonDocument(releases).toJson();
                const int status = notes && notesFail ? 404 : httpStatus;
                socket->write("HTTP/1.1 " + QByteArray::number(status) + " Test\r\nConnection: close\r\nContent-Length: "
                    + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                socket->disconnectFromHost();
            });
        }
    });
    const auto wait = [](UpdateChecker &checker) {
        if (checker.checking()) {
            QEventLoop loop;
            QObject::connect(&checker, &UpdateChecker::changed, &loop, [&] {
                if (!checker.checking()) loop.quit();
            });
            QTimer::singleShot(5000, &loop, &QEventLoop::quit);
            loop.exec();
        }
        assert(!checker.checking());
    };
    const auto waitClosed = [](QObject *dialog) {
        if (!dialog->property("visible").toBool()) return;
        QEventLoop loop;
        QObject::connect(dialog, SIGNAL(closed()), &loop, SLOT(quit()));
        QTimer::singleShot(2000, &loop, &QEventLoop::quit);
        loop.exec();
        assert(!dialog->property("visible").toBool());
    };
    const auto waitOpened = [](QObject *dialog) {
        if (dialog->property("opened").toBool()) return;
        QEventLoop loop;
        QObject::connect(dialog, SIGNAL(opened()), &loop, SLOT(quit()));
        QTimer::singleShot(2000, &loop, &QEventLoop::quit);
        loop.exec();
        assert(dialog->property("opened").toBool());
    };
    QSettings(QStringLiteral("aether64"), QStringLiteral("ReSketch")).setValue("updates/branch", "main");
    UpdateChecker checker(nullptr, "1.2.9", api);
    assert(!checker.managedBySystem());
    assert(checker.currentChangelog().startsWith("1.2.9 -"));
    assert(checker.enabled() && checker.branch() == "main");
    assert(checker.periodicEnabled() && checker.m_periodicTimer.isActive());
    assert(checker.m_periodicTimer.interval() == 5 * 60 * 60 * 1000);
    assert(!checker.m_periodicTimer.isSingleShot());
    int notices = 0;
    QObject::connect(&checker, &UpdateChecker::updateAvailable, [&] { ++notices; });
    checker.checkAtStartup();
    checker.checkAtStartup();
    wait(checker);
    assert(notices == 1 && requests == 2);
    assert(checker.available().value("version") == "1.2.10");
    assert(checker.available().value("url") == "https://github.com/Ralsei-x64/ReSketch/releases/tag/cef-v1.2.10-abcdef0");
    assert(checker.available().value("changelog").toString().contains("Fourth line"));
    assert(!checker.available().value("changelog").toString().contains("Already installed"));
    assert(!checker.available().value("changelog").toString().contains("Newer changes"));

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("testUpdater", &checker);
    engine.loadData(R"(
import QtQuick
import QtQuick.Controls
import "../src" as App
ApplicationWindow {
    visible: true; width: 880; height: 700
    App.UpdateSettings { anchors.fill: parent; updater: testUpdater }
    App.UpdateDialog { updater: testUpdater }
    App.UpdateCompleteDialog { id: complete; updater: testUpdater }
    App.UpdateCompleteDialog { updater: testUpdater; afterRestart: true }
    Connections { target: testUpdater; function onInstallationComplete() { complete.open() } }
})", QUrl::fromLocalFile(QDir::current().absoluteFilePath("tests/update-fixture.qml")));
    assert(!engine.rootObjects().isEmpty());
    auto *window = engine.rootObjects().first();
    const auto snapshot = [&](const QString &state) {
        const auto prefix = qEnvironmentVariable("RESKETCH_UPDATE_SCREENSHOTS");
        if (prefix.isEmpty()) return;
        QCoreApplication::processEvents();
        assert(qobject_cast<QQuickWindow *>(window)->grabWindow().save(prefix + "-" + state + ".png"));
    };
    const auto child = [&](const char *name) { auto *item = window->findChild<QObject *>(QString::fromLatin1(name)); assert(item); return item; };
    assert(!child("systemManagedUpdatesNotice")->property("visible").toBool());
    assert(child("updateControls")->property("enabled").toBool());
    assert(child("updateStatusHeading")->property("text") == "Update Found");
    assert(!window->findChild<QObject *>("updateBranchCombo"));
    assert(child("updateChangelogPreview")->property("maximumLineCount").toInt() == 3);
    assert(child("viewChangelogButton")->property("text") == "Read Changes");
    assert(!child("viewChangelogButton")->property("flat").toBool());
    snapshot("found");
    assert(QMetaObject::invokeMethod(child("startupUpdateCheck"), "toggle"));
    assert(QMetaObject::invokeMethod(child("startupUpdateCheck"), "toggled"));
    assert(!checker.enabled());
    const int beforePeriodic = requests;
    assert(QMetaObject::invokeMethod(&checker.m_periodicTimer, "timeout"));
    assert(checker.checking()); // Startup checks and periodic checks are independent.
    assert(QMetaObject::invokeMethod(&checker.m_periodicTimer, "timeout"));
    wait(checker);
    assert(requests == beforePeriodic + 2 && notices == 2); // No overlapping requests.
    assert(QMetaObject::invokeMethod(child("periodicUpdateCheck"), "toggle"));
    assert(QMetaObject::invokeMethod(child("periodicUpdateCheck"), "toggled"));
    assert(!checker.periodicEnabled() && !checker.m_periodicTimer.isActive());
    { UpdateChecker saved(nullptr, "1.2.9", api); assert(!saved.periodicEnabled() && !saved.m_periodicTimer.isActive()); }
    assert(QMetaObject::invokeMethod(&checker.m_periodicTimer, "timeout"));
    assert(!checker.checking() && requests == beforePeriodic + 2);
    checker.setPeriodicEnabled(true);
    assert(checker.m_periodicTimer.isActive());
    checker.setEnabled(true);
    assert(QMetaObject::invokeMethod(child("viewChangelogButton"), "clicked"));
    auto *notes = child("updateChangelogDialog");
    assert(notes->property("visible").toBool());
    waitOpened(notes);
    snapshot("changelog");
    assert(QMetaObject::invokeMethod(notes, "close"));
    waitClosed(notes);
    auto *dialog = child("updateAvailableDialog");
    assert(QMetaObject::invokeMethod(dialog, "open"));
    waitOpened(dialog);
    assert(dialog->property("title") == "ReSketch has pending updates.");
    assert(child("startUpdateButton")->property("text") == "Update");
    assert(!child("startUpdateButton")->property("enabled").toBool());
    snapshot("dialog");
    assert(QMetaObject::invokeMethod(child("cancelUpdateButton"), "clicked"));
    waitClosed(dialog);
    assert(!dialog->property("visible").toBool());
    assert(checker.m_promptDismissed);
    assert(checker.available().value("version") == "1.2.10");
    {
        UpdateChecker cancelled(nullptr, "1.2.9", api);
        int prompted = 0;
        QObject::connect(&cancelled, &UpdateChecker::updateAvailable, [&] { ++prompted; });
        cancelled.checkAtStartup(); wait(cancelled);
        assert(prompted == 1); // Cancel never persists a skipped version.
    }
    assert(QMetaObject::invokeMethod(dialog, "open"));
    assert(QMetaObject::invokeMethod(child("skipUpdateButton"), "clicked"));
    waitClosed(dialog);
    assert(!dialog->property("visible").toBool());
    {
        UpdateChecker restarted(nullptr, "1.2.9", api);
        int prompted = 0;
        QObject::connect(&restarted, &UpdateChecker::updateAvailable, [&] { ++prompted; });
        restarted.checkAtStartup(); wait(restarted);
        assert(prompted == 0 && !restarted.available().isEmpty());
        restarted.checkForUpdates(); wait(restarted);
        assert(restarted.available().value("version") == "1.2.10");
    }
    const int beforeSkippedPeriodic = notices;
    assert(QMetaObject::invokeMethod(&checker.m_periodicTimer, "timeout"));
    wait(checker);
    assert(notices == beforeSkippedPeriodic && checker.available().value("version") == "1.2.10");
    releases.append(release("cef-v1.3.0-abcdef0"));
    {
        UpdateChecker newer(nullptr, "1.2.9", api);
        int prompted = 0;
        QObject::connect(&newer, &UpdateChecker::updateAvailable, [&] { ++prompted; });
        newer.checkAtStartup(); wait(newer);
        assert(prompted == 1 && newer.available().value("version") == "1.3.0");
    }
    const int beforeDismissedPeriodic = notices;
    assert(QMetaObject::invokeMethod(&checker.m_periodicTimer, "timeout"));
    wait(checker);
    assert(notices == beforeDismissedPeriodic && checker.available().value("version") == "1.3.0");
    checker.setEnabled(false);
    const int before = requests;
    { UpdateChecker disabled(nullptr, "1.2.9", api); disabled.checkAtStartup(); assert(!disabled.checking() && requests == before); }
    checker.checkForUpdates(); wait(checker);
    assert(checker.available().value("version") == "1.3.0");
    olderBranch = true;
    checker.checkForUpdates(); wait(checker);
    assert(pageTwo == 1 && checker.available().value("version") == "1.3.0");
    { UpdateChecker saved(nullptr, "1.2.9", api); assert(!saved.enabled() && saved.branch() == "main"); }
    releases = {release("cef-v1.2.8-abcdef0")}; olderBranch = false;
    checker.checkForUpdates(); wait(checker);
    assert(checker.available().isEmpty() && checker.error().isEmpty());
    QCoreApplication::processEvents();
    assert(child("updateStatusHeading")->property("text") == "You're already on the newest version!");
    assert(child("updateVersionLabel")->property("text") == "1.2.9");
    assert(child("updateChangelogPreview")->property("text") == checker.currentChangelog());
    snapshot("current");
    releases = {release("cef-v9.0.0-abcdef0")}; notesFail = true;
    checker.checkForUpdates(); wait(checker);
    assert(checker.available().value("changelog") == "Release notes fallback");
    malformed = true;
    checker.checkForUpdates(); wait(checker);
    assert(!checker.error().isEmpty() && checker.available().isEmpty());
    malformed = false; httpStatus = 403;
    checker.checkForUpdates(); wait(checker);
    assert(checker.error().contains("limit"));
    QCoreApplication::processEvents();
    assert(child("updateStatusHeading")->property("text") == "Couldn't fetch updates.");
    httpStatus = 200;
    checker.checkForUpdates(); checker.reset();
    assert(!checker.checking() && checker.available().isEmpty());
    checker.reset();
    assert(checker.enabled() && checker.branch() == "main");
    assert(checker.periodicEnabled() && checker.m_periodicTimer.isActive());
    notesFail = false;
    QTemporaryDir installerDirectory;
    assert(installerDirectory.isValid());
    const QString script = installerDirectory.filePath("installer");
    const QString receipt = installerDirectory.filePath("receipt");
    const auto writeInstaller = [&](int exitCode) {
        QFile executable(script);
        assert(executable.open(QIODevice::WriteOnly));
        executable.write(("#!/bin/sh\ntest -f \"$1\" || exit 9\nprintf '%s\\n' \"$1\" > '" + receipt + "'\nexit "
            + QString::number(exitCode) + "\n").toUtf8());
        executable.close();
        assert(executable.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    };
    writeInstaller(0);
    auto installRelease = release("cef-v1.2.10-abcdef0");
    installRelease["assets"] = QJsonArray{QJsonObject{{"name", packageName}}, QJsonObject{{"name", "SHA256SUMS"}}};
    releases = {installRelease};
    UpdateChecker installer(nullptr, "1.2.9", api, api.resolved(QUrl("downloads/")));
    installer.m_installCommand = {script}; // Never invoke pacman or authenticate from tests.
    installer.checkForUpdates(); wait(installer);
    assert(installer.canInstall());
    engine.rootContext()->setContextProperty("testUpdater", &installer);
    const auto waitInstall = [&] {
        QEventLoop loop;
        QObject::connect(&installer, &UpdateChecker::changed, &loop, [&] { if (!installer.installing()) loop.quit(); });
        QTimer::singleShot(5000, &loop, &QEventLoop::quit);
        if (installer.installing()) loop.exec();
        assert(!installer.installing());
    };
    assert(QMetaObject::invokeMethod(dialog, "open"));
    waitOpened(dialog);
    assert(child("startUpdateButton")->property("enabled").toBool());
    assert(QMetaObject::invokeMethod(child("startUpdateButton"), "clicked"));
    assert(installer.installing());
    assert(installer.m_promptDismissed);
    assert(!child("startUpdateButton")->property("enabled").toBool());
    assert(child("updateProgressBar")->property("visible").toBool());
    installer.cancelDownload();
    waitClosed(dialog);
    assert(!installer.installing() && !installer.installed() && !QFile::exists(receipt));
    corruptPackage = true;
    installer.installUpdate(); waitInstall();
    assert(installer.installError().contains("checksum") && !QFile::exists(receipt));
    corruptPackage = false; invalidChecksum = true;
    installer.installUpdate(); waitInstall();
    assert(installer.installError().contains("checksum") && !QFile::exists(receipt));
    invalidChecksum = false;
    writeInstaller(126);
    installer.installUpdate(); waitInstall();
    assert(installer.installError().contains("cancelled") && !installer.installed());
    QFile::remove(receipt);
    writeInstaller(0);
    installer.installUpdate(); waitInstall();
    assert(installer.installed() && installer.installError().isEmpty() && QFile::exists(receipt));
    QFile installedPackage(receipt);
    assert(installedPackage.open(QIODevice::ReadOnly));
    assert(!QFile::exists(QString::fromUtf8(installedPackage.readAll()).trimmed())); // Temporary package removed after installation.
    auto *complete = child("updateCompleteDialog");
    waitOpened(complete);
    assert(complete->property("title") == "Update Complete");
    assert(child("finishUpdateButton")->property("text") == "Finish Update");
    assert(child("updateLaterButton")->property("text") == "Update Later");
    assert(complete->findChild<QObject *>("finishUpdateButton")->property("activeFocus").toBool());
    snapshot("restart-prompt");
    assert(QMetaObject::invokeMethod(child("updateLaterButton"), "clicked"));
    waitClosed(complete);
    assert(installer.installed()); // Deferring restart keeps the completed update available.
    assert(child("installUpdateButton")->property("text") == "Finish Update");
    snapshot("installed-later");
    assert(!child("viewUpdateOnGitHubButton")->property("visible").toBool());
    assert(!child("checkForUpdatesButton")->property("visible").toBool());
    assert(!child("viewChangelogButton")->property("visible").toBool());
    assert(installer.completedUpdate().isEmpty()); // It has not restarted into the new version yet.
    UpdateChecker restarted(nullptr, "1.2.10", api);
    assert(restarted.completedUpdate().value("version") == "1.2.10");
    assert(restarted.completedUpdate().value("changelog").toString().contains("Fourth line"));
    engine.rootContext()->setContextProperty("testUpdater", &restarted);
    auto *postRestart = child("updatedVersionDialog");
    assert(QMetaObject::invokeMethod(postRestart, "open"));
    waitOpened(postRestart);
    snapshot("restarted");
    assert(postRestart->property("title") == "Update Complete");
    assert(postRestart->findChild<QObject *>("updateCompleteSeparator")->property("visible").toBool());
    assert(postRestart->property("height").toDouble() < 400); // Short notes should not reserve an empty full-height editor.
    auto *okay = postRestart->findChild<QObject *>("acknowledgeUpdateButton");
    assert(okay && okay->property("text") == "Okay" && okay->property("visible").toBool());
    assert(okay->property("activeFocus").toBool());
    restarted.m_currentChangelog = "1.2.10 - 2026-10-16\n" + QString("Long release notes that wrap and remain readable in a small window.\n").repeated(60);
    restarted.changed();
    window->setProperty("width", 500);
    window->setProperty("height", 420);
    QEventLoop relayout;
    QTimer::singleShot(100, &relayout, &QEventLoop::quit);
    relayout.exec();
    assert(postRestart->property("height").toDouble() <= 400);
    snapshot("restarted-long");
    assert(QMetaObject::invokeMethod(okay, "clicked"));
    waitClosed(postRestart);
    assert(restarted.completedUpdate().isEmpty());
    { UpdateChecker later(nullptr, "1.2.10", api); assert(later.completedUpdate().isEmpty()); }
    engine.rootContext()->setContextProperty("testUpdater", &checker);
    puts("Update startup, semantic versions, branch pagination, skip persistence, errors, cancellation and QML dialogs passed");
    puts("Update package streaming, checksum verification, cancellation, installer outcomes and restart-later dialog checks passed");
}
