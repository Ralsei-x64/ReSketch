// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QCoreApplication>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QSettings>
#include <QVariantMap>

class QNetworkReply;

class UpdateChecker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed)
    Q_PROPERTY(QString branch READ branch WRITE setBranch NOTIFY changed)
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString currentChangelog READ currentChangelog CONSTANT)
    Q_PROPERTY(bool checking READ checking NOTIFY changed)
    Q_PROPERTY(bool checked READ checked NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QVariantMap available READ available NOTIFY changed)
public:
    explicit UpdateChecker(QObject *parent = nullptr,
        const QString &version = QCoreApplication::applicationVersion(),
        const QUrl &apiRoot = QUrl(QStringLiteral("https://api.github.com/repos/Ralsei-x64/ReSketch/")));
    bool enabled() const;
    QString branch() const;
    QString currentVersion() const { return m_version; }
    QString currentChangelog() const { return m_currentChangelog; }
    bool checking() const { return m_checking; }
    bool checked() const { return m_checked; }
    QString error() const { return m_error; }
    QVariantMap available() const { return m_available; }
    void setEnabled(bool value);
    void setBranch(const QString &value);
    Q_INVOKABLE void checkAtStartup();
    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void skipUpdate();
    Q_INVOKABLE void openRelease() const;
    void reset();
signals:
    void changed();
    void updateAvailable();
private:
    void check(bool startup);
    void requestReleases(int page, quint64 serial);
    void requestChangelog(quint64 serial);
    QNetworkReply *get(const QUrl &url, bool raw = false);
    void finish(const QString &error = {});
    void cancel();
    QSettings m_settings;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    const QString m_version;
    const QUrl m_apiRoot;
    QString m_currentChangelog;
    QVariantMap m_available;
    QString m_error;
    quint64 m_serial = 0;
    bool m_checking = false, m_checked = false, m_startup = false, m_startupAttempted = false;
};
