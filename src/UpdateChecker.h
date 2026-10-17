// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QCoreApplication>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QSettings>
#include <QVariantMap>
#include <QCryptographicHash>
#include <QFile>
#include <QProcess>
#include <QTemporaryDir>
#include <QTimer>
#include <memory>

class QNetworkReply;

class UpdateChecker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool managedBySystem READ managedBySystem CONSTANT)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed)
    Q_PROPERTY(bool periodicEnabled READ periodicEnabled WRITE setPeriodicEnabled NOTIFY changed)
    Q_PROPERTY(QString branch READ branch CONSTANT)
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString currentChangelog READ currentChangelog CONSTANT)
    Q_PROPERTY(bool checking READ checking NOTIFY changed)
    Q_PROPERTY(bool checked READ checked NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QVariantMap available READ available NOTIFY changed)
    Q_PROPERTY(bool installing READ installing NOTIFY changed)
    Q_PROPERTY(bool installed READ installed NOTIFY changed)
    Q_PROPERTY(bool downloading READ downloading NOTIFY changed)
    Q_PROPERTY(bool canInstall READ canInstall NOTIFY changed)
    Q_PROPERTY(double downloadProgress READ downloadProgress NOTIFY changed)
    Q_PROPERTY(QString installStatus READ installStatus NOTIFY changed)
    Q_PROPERTY(QString installError READ installError NOTIFY changed)
    Q_PROPERTY(QVariantMap completedUpdate READ completedUpdate NOTIFY changed)
public:
    bool managedBySystem() const {
#ifdef RESKETCH_DISABLE_UPDATES
        return true;
#else
        return false;
#endif
    }
    explicit UpdateChecker(QObject *parent = nullptr,
        const QString &version = QCoreApplication::applicationVersion(),
        const QUrl &apiRoot = QUrl(QStringLiteral("https://api.github.com/repos/Ralsei-x64/ReSketch/")),
        const QUrl &assetRoot = QUrl(QStringLiteral("https://github.com/Ralsei-x64/ReSketch/releases/download/")));
    bool enabled() const;
    bool periodicEnabled() const;
    QString branch() const;
    QString currentVersion() const { return m_version; }
    QString currentChangelog() const { return m_currentChangelog; }
    bool checking() const { return m_checking; }
    bool checked() const { return m_checked; }
    QString error() const { return m_error; }
    QVariantMap available() const { return m_available; }
    bool installing() const { return m_installing; }
    bool installed() const { return m_installed; }
    bool downloading() const { return m_installing && !m_installer; }
    bool canInstall() const;
    double downloadProgress() const { return m_downloadProgress; }
    QString installStatus() const { return m_installStatus; }
    QString installError() const { return m_installError; }
    QVariantMap completedUpdate() const;
    void setEnabled(bool value);
    void setPeriodicEnabled(bool value);
    Q_INVOKABLE void checkAtStartup();
    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void skipUpdate();
    Q_INVOKABLE void dismissUpdatePrompt() { m_promptDismissed = true; }
    Q_INVOKABLE void openRelease() const;
    Q_INVOKABLE void installUpdate();
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE void finishUpdate();
    Q_INVOKABLE void dismissCompletedUpdate();
    void reset();
signals:
    void changed();
    void updateAvailable();
    void installationComplete();
private:
    friend void checkUpdates();
    void downloadPackage(const QByteArray &checksum);
    void finishInstallation(const QString &error = {});
    enum class Trigger { Startup, Periodic, Manual };
    void check(Trigger trigger);
    void requestReleases(int page, quint64 serial);
    void requestChangelog(quint64 serial);
    QNetworkReply *get(const QUrl &url, bool raw = false);
    void finish(const QString &error = {});
    void cancel();
    QSettings m_settings;
    QNetworkAccessManager m_network;
    QTimer m_periodicTimer;
    QPointer<QNetworkReply> m_reply;
    const QString m_version;
    const QUrl m_apiRoot;
    const QUrl m_assetRoot;
    QString m_currentChangelog;
    QVariantMap m_available;
    QString m_error;
    quint64 m_serial = 0;
    Trigger m_trigger = Trigger::Manual;
    bool m_checking = false, m_checked = false, m_startupAttempted = false;
    bool m_installing = false, m_installed = false, m_promptDismissed = false;
    double m_downloadProgress = 0;
    QString m_installStatus, m_installError;
    QPointer<QNetworkReply> m_downloadReply;
    std::unique_ptr<QTemporaryDir> m_downloadDirectory;
    QFile m_package;
    QCryptographicHash m_packageHash{QCryptographicHash::Sha256};
    QProcess *m_installer = nullptr;
    QStringList m_installCommand{QStringLiteral("/usr/bin/pkexec"), QStringLiteral("/usr/bin/pacman"),
                               QStringLiteral("-U"), QStringLiteral("--noconfirm")};
};
