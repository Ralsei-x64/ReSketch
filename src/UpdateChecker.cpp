// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "UpdateChecker.h"
#include <QDesktopServices>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QUrlQuery>
#include <QVersionNumber>

namespace {
QString releaseNotes(const QString &text, const QVersionNumber &version, const QVersionNumber &after = {})
{
    const QRegularExpression header("^([0-9]+\\.[0-9]+\\.[0-9]+) - [^\\n]+$", QRegularExpression::MultilineOption);
    auto matches = header.globalMatch(text);
    QStringList changes;
    QRegularExpressionMatch previous;
    const auto append = [&](qsizetype end) {
        if (!previous.hasMatch()) return;
        const auto entry = QVersionNumber::fromString(previous.captured(1));
        if (after.isNull() ? entry == version : entry > after && entry <= version)
            changes.append(text.mid(previous.capturedStart(), end - previous.capturedStart()).trimmed());
    };
    while (matches.hasNext()) {
        const auto next = matches.next();
        append(next.capturedStart());
        previous = next;
    }
    append(text.size());
    return changes.join("\n\n");
}
}

UpdateChecker::UpdateChecker(QObject *parent, const QString &version, const QUrl &apiRoot)
    : QObject(parent), m_settings(QStringLiteral("aether64"), QStringLiteral("ReSketch")),
      m_network(this), m_version(version), m_apiRoot(apiRoot)
{
    QFile notes(QStringLiteral(":/CHANGELOG.txt"));
    if (notes.open(QIODevice::ReadOnly))
        m_currentChangelog = releaseNotes(QString::fromUtf8(notes.readAll()), QVersionNumber::fromString(m_version));
    if (m_currentChangelog.isEmpty()) m_currentChangelog = tr("No changelog was provided for this version.");
}

bool UpdateChecker::enabled() const { return m_settings.value("updates/startup", true).toBool(); }
QString UpdateChecker::branch() const { return m_settings.value("updates/branch", "resketch-cef").toString(); }

void UpdateChecker::setEnabled(bool value)
{
    if (enabled() == value) return;
    m_settings.setValue("updates/startup", value);
    if (!value && m_checking && m_startup) cancel();
    emit changed();
}

void UpdateChecker::setBranch(const QString &value)
{
    if ((value != "resketch-cef" && value != "main") || value == branch()) return;
    cancel();
    m_settings.setValue("updates/branch", value);
    emit changed();
}

void UpdateChecker::cancel()
{
    ++m_serial;
    if (m_reply) m_reply->abort();
    m_reply = nullptr;
    m_checking = m_checked = false;
    m_error.clear();
    m_available.clear();
}

void UpdateChecker::reset()
{
    cancel();
    m_settings.remove("updates");
    emit changed();
}

void UpdateChecker::checkAtStartup()
{
    if (m_startupAttempted || !enabled()) return;
    m_startupAttempted = true;
    check(true);
}

void UpdateChecker::checkForUpdates()
{
    m_startupAttempted = true; // A manual check also satisfies this launch's startup check.
    check(false);
}

void UpdateChecker::check(bool startup)
{
    if (m_checking) return;
    cancel();
    m_startup = startup;
    m_checking = true;
    emit changed();
    requestReleases(1, m_serial);
}

QNetworkReply *UpdateChecker::get(const QUrl &url, bool raw)
{
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "ReSketch/" + m_version.toUtf8());
    request.setRawHeader("Accept", raw ? "application/vnd.github.raw+json" : "application/vnd.github+json");
    request.setRawHeader("X-GitHub-Api-Version", "2026-03-10");
    request.setTransferTimeout(15000);
    m_reply = m_network.get(request);
    connect(m_reply, &QNetworkReply::downloadProgress, m_reply, [reply = m_reply](qint64 received, qint64 total) {
        if (reply && (received > 2 * 1024 * 1024 || total > 2 * 1024 * 1024)) reply->abort();
    });
    return m_reply;
}

void UpdateChecker::requestReleases(int page, quint64 serial)
{
    QUrl url = m_apiRoot.resolved(QUrl("releases"));
    QUrlQuery query;
    query.addQueryItem("per_page", "100");
    query.addQueryItem("page", QString::number(page));
    url.setQuery(query);
    auto *reply = get(url);
    connect(reply, &QNetworkReply::finished, this, [this, reply, page, serial] {
        reply->deleteLater();
        if (serial != m_serial) return;
        if (reply->error() != QNetworkReply::NoError) {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            finish(status == 403 || status == 429 ? tr("GitHub's request limit was reached. Please try again later.")
                                                : tr("Could not check for updates: %1").arg(reply->errorString()));
            return;
        }
        QJsonParseError parse;
        const auto document = QJsonDocument::fromJson(reply->readAll(), &parse);
        if (parse.error != QJsonParseError::NoError || !document.isArray()) {
            finish(tr("GitHub returned an invalid release list."));
            return;
        }
        const QString prefix = branch() == "main" ? "main" : "cef";
        const QRegularExpression tagPattern("^" + prefix + "-v([0-9]+\\.[0-9]+\\.[0-9]+)-[0-9a-f]{7,40}$");
        QVersionNumber newest;
        bool foundBranch = false;
        for (const auto &value : document.array()) {
            const auto release = value.toObject();
            const auto tag = release.value("tag_name").toString();
            const auto match = tagPattern.match(tag);
            if (!match.hasMatch() || release.value("draft").toBool()
                || (branch() == "main" && release.value("prerelease").toBool())) continue;
            foundBranch = true;
            const auto version = QVersionNumber::fromString(match.captured(1));
            if (version.segmentCount() != 3 || version <= QVersionNumber::fromString(m_version) || version <= newest) continue;
            newest = version;
            m_available = {{"version", match.captured(1)}, {"branch", branch()}, {"tag", tag},
                           {"url", "https://github.com/Ralsei-x64/ReSketch/releases/tag/" + tag},
                           {"changelog", release.value("body").toString().trimmed()}};
        }
        // One branch can have many releases before the other branch appears.
        if (!foundBranch && document.array().size() == 100) requestReleases(page + 1, serial);
        else if (!m_available.isEmpty()) requestChangelog(serial);
        else finish();
    });
}

void UpdateChecker::requestChangelog(quint64 serial)
{
    QUrl url = m_apiRoot.resolved(QUrl("contents/CHANGELOG.txt"));
    QUrlQuery query;
    query.addQueryItem("ref", m_available.value("tag").toString());
    url.setQuery(query);
    auto *reply = get(url, true);
    connect(reply, &QNetworkReply::finished, this, [this, reply, serial] {
        reply->deleteLater();
        if (serial != m_serial) return;
        if (reply->error() == QNetworkReply::NoError) {
            const QString text = QString::fromUtf8(reply->readAll());
            const QString changes = releaseNotes(text, QVersionNumber::fromString(m_available.value("version").toString()),
                                                QVersionNumber::fromString(m_version));
            if (!changes.isEmpty()) m_available["changelog"] = changes;
        }
        if (m_available.value("changelog").toString().isEmpty())
            m_available["changelog"] = tr("No changelog was provided for this release.");
        finish();
    });
}

void UpdateChecker::finish(const QString &error)
{
    m_reply = nullptr;
    m_checking = false;
    m_checked = true;
    m_error = error;
    if (!error.isEmpty()) m_available.clear();
    emit changed();
    const auto skipped = QVersionNumber::fromString(m_settings.value("updates/skipped/" + branch()).toString());
    if (m_startup && !m_available.isEmpty()
        && QVersionNumber::fromString(m_available.value("version").toString()) > skipped) emit updateAvailable();
}

void UpdateChecker::skipUpdate()
{
    if (m_available.isEmpty()) return;
    m_settings.setValue("updates/skipped/" + branch(), m_available.value("version"));
}

void UpdateChecker::openRelease() const
{
    if (!m_available.isEmpty()) QDesktopServices::openUrl(QUrl(m_available.value("url").toString()));
}
