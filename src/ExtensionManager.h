// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include "include/cef_base.h"
#include <QJsonObject>
#include <QMap>
#include <QNetworkAccessManager>
#include <QSettings>
#include <QSet>
#include <QTimer>
#include <QVariantList>
#include <QWebSocket>
#include <functional>

class ExtensionControl;
class ExtensionManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QVariantList extensions READ extensions NOTIFY changed)
public:
    explicit ExtensionManager(QObject *parent = nullptr, bool available = true);
    ~ExtensionManager() override;
    bool available() const { return m_available; }
    QString error() const { return m_error; }
    QVariantList extensions() const;
    Q_INVOKABLE void choosePackage();
    Q_INVOKABLE bool installPackage(const QString &file);
    Q_INVOKABLE void setExtensionEnabled(const QString &key, bool enabled);
    Q_INVOKABLE void removeExtension(const QString &key);
    Q_INVOKABLE QUrl extensionPage(const QString &key, bool options) const;
    void shutdown();
signals:
    void changed();
    void pageRequested(QUrl url, QString key);
private:
    using Callback = std::function<void(QJsonObject)>;
    void connectBrowser();
    void reconcile();
    void releaseControl();
    void parkControl();
    void command(const QString &method, QJsonObject params, Callback callback);
    void save();
    QString root() const;
    QSettings m_settings;
    QNetworkAccessManager m_network;
    QWebSocket m_socket;
    QTimer m_retry;
    QMap<int, Callback> m_callbacks;
    QVariantList m_extensions;
    QMap<QString, QString> m_loaded, m_failures;
    QSet<QString> m_enabled;
    bool m_available, m_connecting = false, m_busy = false, m_managementReady = false;
    int m_serial = 0;
    QString m_error;
    CefRefPtr<ExtensionControl> m_control;
};
