// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QFile>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QProcess>
#include <QSettings>
#include <QTemporaryDir>
#include <QVariantMap>
#include <memory>

class QNetworkReply;

class UpdateChecker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool managedBySystem READ managedBySystem CONSTANT)
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString currentChangelog READ currentChangelog CONSTANT)
    Q_PROPERTY(QVariantMap available READ available NOTIFY changed)
    Q_PROPERTY(bool installing READ installing NOTIFY changed)
    Q_PROPERTY(bool installed READ installed NOTIFY changed)
    Q_PROPERTY(bool downloading READ downloading NOTIFY changed)
    Q_PROPERTY(bool canMigrate READ canMigrate NOTIFY changed)
    Q_PROPERTY(double downloadProgress READ downloadProgress NOTIFY changed)
    Q_PROPERTY(QString installStatus READ installStatus NOTIFY changed)
    Q_PROPERTY(QString installError READ installError NOTIFY changed)
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
    QString currentVersion() const { return m_version; }
    QString currentChangelog() const { return m_currentChangelog; }
    QVariantMap available() const { return m_available; }
    bool installing() const { return m_installing; }
    bool installed() const { return m_installed; }
    bool downloading() const { return m_installing && !m_installer; }
    bool canMigrate() const;
    double downloadProgress() const { return m_downloadProgress; }
    QString installStatus() const { return m_installStatus; }
    QString installError() const { return m_installError; }
    Q_INVOKABLE void migrateToMain();
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE void finishUpdate();
signals:
    void changed();
    void installationComplete();
private:
    friend void checkMigration();
    void requestReleases(int page);
    void installUpdate();
    void downloadPackage(const QByteArray &checksum);
    void finishInstallation(const QString &error = {});
    QSettings m_settings;
    QNetworkAccessManager m_network;
    const QString m_version;
    const QUrl m_apiRoot, m_assetRoot;
    QVariantMap m_available;
    QString m_currentChangelog;
    bool m_installing = false, m_installed = false;
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
