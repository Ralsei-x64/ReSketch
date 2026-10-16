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
                if (notes) body = changelog.toUtf8();
                else if (malformed) body = "not json";
                else if (olderBranch && !secondPage) {
                    QJsonArray page;
                    for (int i = 0; i < 100; ++i) page.append(release("cef-v1.2.10-abcdef0"));
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
    UpdateChecker checker(nullptr, "1.2.9", api);
    assert(checker.currentChangelog().startsWith("1.2.9 -"));
    assert(checker.enabled() && checker.branch() == "resketch-cef");
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
    assert(child("updateStatusHeading")->property("text") == "Update Found");
    assert(child("updateChangelogPreview")->property("maximumLineCount").toInt() == 3);
    snapshot("found");
    assert(QMetaObject::invokeMethod(child("startupUpdateCheck"), "toggle"));
    assert(QMetaObject::invokeMethod(child("startupUpdateCheck"), "toggled"));
    assert(!checker.enabled());
    checker.setEnabled(true);
    assert(QMetaObject::invokeMethod(child("viewChangelogButton"), "clicked"));
    auto *notes = child("updateChangelogDialog");
    assert(notes->property("visible").toBool());
    assert(QMetaObject::invokeMethod(notes, "close"));
    waitClosed(notes);
    auto *dialog = child("updateAvailableDialog");
    assert(QMetaObject::invokeMethod(dialog, "open"));
    waitOpened(dialog);
    assert(dialog->property("title") == "ReSketch has pending updates.");
    snapshot("dialog");
    assert(QMetaObject::invokeMethod(child("cancelUpdateButton"), "clicked"));
    waitClosed(dialog);
    assert(!dialog->property("visible").toBool());
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
    releases.append(release("cef-v1.3.0-abcdef0"));
    {
        UpdateChecker newer(nullptr, "1.2.9", api);
        int prompted = 0;
        QObject::connect(&newer, &UpdateChecker::updateAvailable, [&] { ++prompted; });
        newer.checkAtStartup(); wait(newer);
        assert(prompted == 1 && newer.available().value("version") == "1.3.0");
    }
    checker.setEnabled(false);
    const int before = requests;
    { UpdateChecker disabled(nullptr, "1.2.9", api); disabled.checkAtStartup(); assert(!disabled.checking() && requests == before); }
    checker.checkForUpdates(); wait(checker);
    assert(checker.available().value("version") == "1.3.0");
    checker.setBranch("main");
    olderBranch = true;
    checker.checkForUpdates(); wait(checker);
    assert(pageTwo == 1 && checker.available().value("version") == "9.0.0");
    { UpdateChecker saved(nullptr, "1.2.9", api); assert(!saved.enabled() && saved.branch() == "main"); }
    releases = {release("main-v0.3.8-abcdef0")}; olderBranch = false;
    checker.checkForUpdates(); wait(checker);
    assert(checker.available().isEmpty() && checker.error().isEmpty());
    QCoreApplication::processEvents();
    assert(child("updateStatusHeading")->property("text") == "You're already on the newest version!");
    assert(child("updateVersionLabel")->property("text") == "1.2.9");
    assert(child("updateChangelogPreview")->property("text") == checker.currentChangelog());
    snapshot("current");
    releases = {release("main-v9.0.0-abcdef0")}; notesFail = true;
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
    checker.checkForUpdates(); checker.setBranch("resketch-cef");
    assert(!checker.checking() && checker.available().isEmpty());
    checker.reset();
    assert(checker.enabled() && checker.branch() == "resketch-cef");
    puts("Update startup, semantic versions, branch pagination, skip persistence, errors, cancellation and QML dialogs passed");
}
