// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#define main resketchMain
#include "../src/main.cpp"
#undef main
#include <QElapsedTimer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QQmlComponent>
#include <QTemporaryDir>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTest>
#include <cassert>
#include "extensions.test.h"

int main(int argc, char **argv) {
    setbuf(stdout, nullptr);
    setbuf(stderr, nullptr);
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    qputenv("RESKETCH_CEF_FLAGS", "--disable-gpu --no-sandbox");
    KIconTheme::initTheme();
    QApplication app(argc, argv);
    QTemporaryDir temporary;
    assert(temporary.isValid());
    const auto runtime = temporary.path() + "/runtime";
    QDir().mkpath(runtime);
    QFile::setPermissions(runtime, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    qputenv("XDG_RUNTIME_DIR", runtime.toUtf8());
    qputenv("RESKETCH_CEF_CACHE_ROOT", (temporary.path() + "/cef").toUtf8());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, temporary.path());
    AppSettings settings;
    settings.setMenuIntegration(false);
    settings.setReduceMotion(true);
    QQmlApplicationEngine engine;
    engine.addImportPath(QDir::current().absoluteFilePath("build-cef/qml"));
    engine.rootContext()->setContextProperty("appSettings", &settings);
    engine.load(QUrl::fromLocalFile(QDir::current().absoluteFilePath("src/Main.qml")));
    assert(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    assert(window);
    checkExtensions(settings, window);
}
