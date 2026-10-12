// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "FontHelper.h"
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSet>
#include <QStringConverter>
#include <QTcpSocket>
#include <QTimer>
#include <QUrlQuery>
#include <QtConcurrentRun>
#include <fontconfig/fontconfig.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_SFNT_NAMES_H
#include FT_TRUETYPE_TABLES_H
#include FT_MULTIPLE_MASTERS_H

static QString fontName(FT_Face face, FT_UInt id, const QString &fallback = {})
{
    for (FT_UInt i = 0; i < FT_Get_Sfnt_Name_Count(face); ++i) {
        FT_SfntName name{};
        if (FT_Get_Sfnt_Name(face, i, &name) || name.name_id != id) continue;
        if (name.platform_id == 0 || (name.platform_id == 3 && name.language_id == 0x409))
            return QStringDecoder(QStringDecoder::Utf16BE)(QByteArrayView(reinterpret_cast<char *>(name.string), name.string_len));
    }
    return fallback;
}

QJsonObject FontHelper::scanFonts()
{
    QJsonObject result;
    FcConfig *config = FcInitLoadConfigAndFonts();
    FT_Library library{};
    if (!config || FT_Init_FreeType(&library)) {
        if (config) FcConfigDestroy(config);
        return result;
    }
    FcPattern *pattern = FcPatternCreate();
    FcObjectSet *objects = FcObjectSetBuild(FC_FILE, nullptr);
    FcFontSet *set = FcFontList(config, pattern, objects);
    QSet<QString> paths;
    if (set) {
        for (int i = 0; i < set->nfont; ++i) {
            FcChar8 *file = nullptr;
            if (FcPatternGetString(set->fonts[i], FC_FILE, 0, &file) == FcResultMatch)
                paths.insert(QFileInfo(QString::fromUtf8(reinterpret_cast<char *>(file))).canonicalFilePath());
        }
        FcFontSetDestroy(set);
    }
    FcObjectSetDestroy(objects);
    FcPatternDestroy(pattern);
    FcConfigDestroy(config);
    for (const QString &path : paths) {
        const QFileInfo info(path);
        if (path.isEmpty() || !info.isReadable()) continue;
        const auto extension = info.suffix().toLower();
        if (extension != "ttf" && extension != "otf" && extension != "ttc" && extension != "otc") continue;
        const QByteArray file = QFile::encodeName(path);
        FT_Face face{};
        if (FT_New_Face(library, file.constData(), -1, &face)) continue;
        const int count = face->num_faces;
        FT_Done_Face(face);
        QJsonArray faces;
        for (int index = 0; index < count; ++index) {
            int instances = 0;
            for (int instance = 0; instance <= instances; ++instance) {
                if (FT_New_Face(library, file.constData(), index | (instance << 16), &face)) continue;
                if (!instance) instances = face->style_flags >> 16;
                const char *postscript = FT_Get_Postscript_Name(face);
                if (!postscript || !FT_IS_SFNT(face)) { FT_Done_Face(face); continue; }
                auto *os2 = static_cast<TT_OS2 *>(FT_Get_Sfnt_Table(face, ft_sfnt_os2));
                int weight = os2 ? os2->usWeightClass : (face->style_flags & FT_STYLE_FLAG_BOLD ? 700 : 400);
                int stretch = os2 ? os2->usWidthClass : 5;
                bool italic = face->style_flags & FT_STYLE_FLAG_ITALIC;
                QString family = fontName(face, 16, fontName(face, 1, QString::fromUtf8(face->family_name)));
                QString style = fontName(face, 17, fontName(face, 2, QString::fromUtf8(face->style_name)));
                QJsonArray axes;
                FT_MM_Var *variation = nullptr;
                if (!FT_Get_MM_Var(face, &variation)) {
                    if (instance && instance <= int(variation->num_namedstyles))
                        style = fontName(face, variation->namedstyle[instance - 1].strid, style);
                    for (FT_UInt a = 0; a < variation->num_axis; ++a) {
                        const auto &axis = variation->axis[a];
                        char tag[5]{char(axis.tag >> 24), char(axis.tag >> 16), char(axis.tag >> 8), char(axis.tag), 0};
                        const double value = (instance ? variation->namedstyle[instance - 1].coords[a] : axis.def) / 65536.0;
                        FT_UInt flags = 0;
                        FT_Get_Var_Axis_Flags(variation, a, &flags);
                        axes.append(QJsonObject{{"tag", QString::fromLatin1(tag)}, {"name", fontName(face, axis.strid, QString::fromUtf8(axis.name))},
                                                {"value", value}, {"min", axis.minimum / 65536.0}, {"max", axis.maximum / 65536.0},
                                                {"default", axis.def / 65536.0}, {"hidden", bool(flags & FT_VAR_AXIS_FLAG_HIDDEN)}});
                        if (axis.tag == FT_MAKE_TAG('w','g','h','t')) weight = qRound(value);
                        if (axis.tag == FT_MAKE_TAG('i','t','a','l')) italic = value != 0;
                        if (axis.tag == FT_MAKE_TAG('s','l','n','t')) italic |= value != 0;
                        if (axis.tag == FT_MAKE_TAG('w','d','t','h')) {
                            const double widths[] = {50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200};
                            stretch = 1;
                            for (int w = 1; w < 9; ++w)
                                if (qAbs(value - widths[w]) < qAbs(value - widths[stretch - 1])) stretch = w + 1;
                        }
                    }
                    FT_Done_MM_Var(library, variation);
                }
                QJsonObject entry{{"family", family}, {"style", style}, {"postscript", QString::fromUtf8(postscript)},
                                  {"weight", weight}, {"stretch", stretch}, {"italic", italic},
                                  {"modified_at", info.lastModified().toSecsSinceEpoch()},
                                  {"user_installed", path.startsWith(QDir::homePath() + '/') }};
                if (!axes.isEmpty()) entry.insert("variationAxes", axes);
                if (!family.isEmpty() && !style.isEmpty()) faces.append(entry);
                FT_Done_Face(face);
            }
        }
        if (!faces.isEmpty()) result.insert(path, faces);
    }
    FT_Done_FreeType(library);
    return result;
}

FontHelper::FontHelper(QObject *parent, quint16 port) : QObject(parent)
{
    connect(&scan, &QFutureWatcher<QJsonObject>::finished, this, [this] {
        fonts = scan.result();
        age.restart();
        const auto pending = waiting;
        waiting.clear();
        for (auto *socket : pending) {
            reply(socket, 200, QJsonDocument(QJsonObject{{"fontFiles", fonts}, {"version", 23}, {"package", "ReSketch"}}).toJson(QJsonDocument::Compact),
                  socket->property("origin").toByteArray());
        }
    });
    connect(&server, &QTcpServer::newConnection, this, [this] {
        while (auto *socket = server.nextPendingConnection()) {
            socket->setReadBufferSize(16385);
            auto *timeout = new QTimer(socket);
            timeout->setSingleShot(true);
            timeout->start(10000);
            connect(timeout, &QTimer::timeout, socket, &QTcpSocket::abort);
            connect(socket, &QTcpSocket::disconnected, this, [this, socket] {
                waiting.removeAll(socket);
                socket->deleteLater();
            });
            connect(socket, &QTcpSocket::readyRead, this, [this, socket] {
                if (socket->property("handled").toBool()) return;
                QByteArray headers = socket->property("headers").toByteArray() + socket->readAll();
                if (headers.size() > 16384) { socket->abort(); return; }
                const int end = headers.indexOf("\r\n\r\n");
                if (end < 0) { socket->setProperty("headers", headers); return; }
                socket->setProperty("handled", true);
                request(socket, headers.left(end));
            });
        }
    });
    if (!server.listen(QHostAddress::LocalHost, port)) {
        // An existing compatible font agent can service Figma on this port.
        qWarning("ReSketch: local font helper: %s", qPrintable(server.errorString()));
        return;
    }
    scan.setFuture(QtConcurrent::run(&FontHelper::scanFonts));
}

void FontHelper::request(QTcpSocket *socket, const QByteArray &headers)
{
    const auto lines = headers.split('\n');
    const auto first = lines.first().trimmed().split(' ');
    QByteArray origin, host;
    for (const auto &line : lines) {
        const int colon = line.indexOf(':');
        const auto name = line.left(colon).trimmed().toLower();
        if (name == "origin") origin = line.mid(colon + 1).trimmed();
        if (name == "host") host = line.mid(colon + 1).trimmed();
    }
    const QUrl from(QString::fromUtf8(origin));
    const bool allowed = from.scheme() == "https" && from.userInfo().isEmpty() && from.port(443) == 443
                         && (from.host() == "figma.com" || from.host().endsWith(".figma.com"))
                         && (from.path().isEmpty() || from.path() == "/") && !from.hasQuery() && !from.hasFragment();
    if (!allowed || host != "127.0.0.1:" + QByteArray::number(port())) { reply(socket, 403, "{}"); return; }
    if (first.size() != 3) { reply(socket, 400, "{}", origin); return; }
    const QUrl url(QString::fromUtf8(first[1]));
    if (first[0] == "OPTIONS") { reply(socket, 204, {}, origin); return; }
    if (first[0] != "GET") { reply(socket, 405, "{}", origin); return; }
    if (url.path() == "/figma/version")
        reply(socket, 200, "{\"version\":23,\"package\":\"ReSketch\"}", origin);
    else if (url.path() == "/figma/font-files") {
        socket->setProperty("origin", origin);
        waiting.append(socket);
        if (!scan.isRunning()) {
            // Rescan off the UI thread so newly installed fonts appear on reload.
            if (!age.isValid() || age.elapsed() > 30000) scan.setFuture(QtConcurrent::run(&FontHelper::scanFonts));
            else {
                waiting.removeAll(socket);
                reply(socket, 200, QJsonDocument(QJsonObject{{"fontFiles", fonts}, {"version", 23}, {"package", "ReSketch"}}).toJson(QJsonDocument::Compact), origin);
            }
        }
    } else if (url.path() == "/figma/font-file") {
        const QString path = QUrlQuery(url).queryItemValue("file", QUrl::FullyDecoded);
        QFile file(path);
        if (!fonts.contains(path) || QFileInfo(path).canonicalFilePath() != path
                || !file.open(QIODevice::ReadOnly) || file.size() > 256 * 1024 * 1024)
            reply(socket, 404, "{}", origin);
        else reply(socket, 200, file.readAll(), origin, "application/octet-stream");
    } else reply(socket, 404, "{}", origin);
}

void FontHelper::reply(QTcpSocket *socket, int status, const QByteArray &body, const QByteArray &origin, const QByteArray &type)
{
    QByteArray response = "HTTP/1.1 " + QByteArray::number(status) + " Response\r\nConnection: close\r\nCache-Control: no-store\r\n";
    if (!origin.isEmpty())
        response += "Access-Control-Allow-Origin: " + origin + "\r\nVary: Origin\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, Accept\r\nAccess-Control-Allow-Private-Network: true\r\n";
    response += "Content-Type: " + type + "\r\nContent-Length: " + QByteArray::number(body.size()) + "\r\n\r\n";
    socket->write(response);
    socket->write(body);
    socket->disconnectFromHost();
}
