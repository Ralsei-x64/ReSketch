// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QFutureWatcher>
#include <QJsonObject>
#include <QTcpServer>
#include <QElapsedTimer>

// Figma's loopback font-agent protocol. Only enumerated fonts are readable,
// and only HTTPS Figma origins may request them.
class FontHelper : public QObject
{
public:
    explicit FontHelper(QObject *parent = nullptr, quint16 port = 44950);
    quint16 port() const { return server.serverPort(); }
    static QJsonObject scanFonts();

private:
    void request(QTcpSocket *socket, const QByteArray &headers);
    void reply(QTcpSocket *socket, int status, const QByteArray &body,
               const QByteArray &origin = {}, const QByteArray &type = "application/json");
    QTcpServer server;
    QFutureWatcher<QJsonObject> scan;
    QJsonObject fonts;
    QElapsedTimer age;
    QList<QTcpSocket *> waiting;
};
