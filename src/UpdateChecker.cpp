// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "UpdateChecker.h"
#ifndef RESKETCH_DISABLE_UPDATES
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSysInfo>
#include <QUrlQuery>
#include <QVersionNumber>

UpdateChecker::UpdateChecker(QObject *parent, const QString &version, const QUrl &apiRoot, const QUrl &assetRoot)
    : QObject(parent), m_settings(QStringLiteral("aether64"), QStringLiteral("ReSketch")),
      m_network(this), m_version(version), m_apiRoot(apiRoot), m_assetRoot(assetRoot)
{
    QFile notes(QStringLiteral(":/CHANGELOG.txt"));
    m_currentChangelog = notes.open(QIODevice::ReadOnly) ? QString::fromUtf8(notes.readAll())
        : tr("No changelog was provided for this version.");
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this] {
        if (m_installer && m_installer->state() != QProcess::NotRunning) m_installer->waitForFinished(-1);
    });
}

bool UpdateChecker::canMigrate() const
{
    return !m_installing && !m_installed && QSysInfo::currentCpuArchitecture() == "x86_64"
        && QFile::exists(m_installCommand.value(0)) && QFile::exists("/usr/bin/pacman");
}

void UpdateChecker::migrateToMain()
{
    if (!canMigrate()) return;
    m_installing = true;
    m_available.clear();
    m_installError.clear();
    m_installStatus = tr("Finding the latest version…");
    m_downloadProgress = -1;
    emit changed();
    requestReleases(1);
}

void UpdateChecker::requestReleases(int page)
{
    QUrl url = m_apiRoot.resolved(QUrl("releases"));
    QUrlQuery query;
    query.addQueryItem("per_page", "100");
    query.addQueryItem("page", QString::number(page));
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "ReSketch/" + m_version.toUtf8());
    request.setRawHeader("Accept", "application/vnd.github+json");
    request.setRawHeader("X-GitHub-Api-Version", "2026-03-10");
    request.setTransferTimeout(15000);
    auto *reply = m_network.get(request);
    reply->setReadBufferSize(2 * 1024 * 1024);
    m_downloadReply = reply;
    connect(reply, &QNetworkReply::downloadProgress, reply, [reply](qint64 received, qint64 total) {
        if (received > 2 * 1024 * 1024 || total > 2 * 1024 * 1024) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, page] {
        reply->deleteLater();
        if (m_downloadReply != reply) return;
        m_downloadReply = nullptr;
        if (reply->error() != QNetworkReply::NoError) {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            finishInstallation(status == 403 || status == 429 ? tr("GitHub's request limit was reached. Please try again later.")
                : tr("Could not find the new version: %1").arg(reply->errorString()));
            return;
        }
        QJsonParseError parse;
        const auto document = QJsonDocument::fromJson(reply->readAll(), &parse);
        if (parse.error != QJsonParseError::NoError || !document.isArray()) {
            finishInstallation(tr("GitHub returned an invalid release list."));
            return;
        }
        const QRegularExpression tagPattern("^cef-v([0-9]+\\.[0-9]+\\.[0-9]+)-[0-9a-f]{7,40}$");
        QVersionNumber newest;
        for (const auto &value : document.array()) {
            const auto release = value.toObject();
            const auto tag = release.value("tag_name").toString();
            const auto match = tagPattern.match(tag);
            if (!match.hasMatch() || release.value("draft").toBool() || release.value("prerelease").toBool()) continue;
            const auto version = QVersionNumber::fromString(match.captured(1));
            if (version.segmentCount() != 3 || version <= newest) continue;
            const QString package = "resketch-cef-" + match.captured(1) + "-"
                + tag.section('-', -1) + "-x86_64.pkg.tar.zst";
            bool hasPackage = false, hasChecksums = false;
            for (const auto &asset : release.value("assets").toArray()) {
                const auto name = asset.toObject().value("name").toString();
                hasPackage |= name == package;
                hasChecksums |= name == "SHA256SUMS";
            }
            if (!hasPackage || !hasChecksums) continue;
            newest = version;
            m_available = {{"version", match.captured(1)}, {"tag", tag}, {"package", package},
                           {"changelog", release.value("body").toString().trimmed()}};
        }
        if (!m_available.isEmpty()) installUpdate();
        else if (document.array().size() == 100) requestReleases(page + 1);
        else finishInstallation(tr("No installable stable version is available. Please try again later."));
    });
}

void UpdateChecker::installUpdate()
{
    m_installing = true;
    m_installError.clear();
    m_installStatus = tr("Fetching checksums…");
    m_downloadProgress = 0;
    emit changed();
    const QString path = m_available.value("tag").toString() + "/SHA256SUMS";
    QNetworkRequest request(m_assetRoot.resolved(QUrl(path)));
    request.setTransferTimeout(30000);
    auto *reply = m_network.get(request);
    reply->setReadBufferSize(256 * 1024);
    m_downloadReply = reply;
    connect(reply, &QNetworkReply::downloadProgress, reply, [reply](qint64 received, qint64 total) {
        if (received > 65536 || total > 65536) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (m_downloadReply != reply) return;
        m_downloadReply = nullptr;
        if (reply->error() != QNetworkReply::NoError) {
            finishInstallation(tr("Couldn't download update checksums: %1").arg(reply->errorString()));
            return;
        }
        const auto package = m_available.value("package").toString();
        const QRegularExpression linePattern("^([0-9a-fA-F]{64}) [ *]" + QRegularExpression::escape(package) + "$",
                                             QRegularExpression::MultilineOption);
        const auto match = linePattern.match(QString::fromUtf8(reply->readAll()));
        if (!match.hasMatch()) {
            finishInstallation(tr("The release has no valid checksum for this package."));
            return;
        }
        downloadPackage(QByteArray::fromHex(match.captured(1).toLatin1()));
    });
}

void UpdateChecker::downloadPackage(const QByteArray &checksum)
{
    m_downloadDirectory = std::make_unique<QTemporaryDir>(QDir::tempPath() + "/resketch-update-XXXXXX");
    m_package.setFileName(m_downloadDirectory->filePath(m_available.value("package").toString()));
    if (!m_downloadDirectory->isValid() || !m_package.open(QIODevice::WriteOnly)) {
        finishInstallation(tr("Couldn't create the update download file."));
        return;
    }
    m_packageHash.reset();
    m_installStatus = tr("Downloading update…");
    emit changed();
    const QString path = m_available.value("tag").toString() + "/" + m_available.value("package").toString();
    QNetworkRequest request(m_assetRoot.resolved(QUrl(path)));
    request.setTransferTimeout(60000);
    auto *reply = m_network.get(request);
    reply->setReadBufferSize(256 * 1024);
    m_downloadReply = reply;
    const auto consume = [this, reply] {
        if (!m_installing || !m_package.isOpen()) return;
        const QByteArray chunk = reply->readAll();
        if (m_package.size() + chunk.size() > qint64(2) * 1024 * 1024 * 1024
            || m_package.write(chunk) != chunk.size()) {
            m_installError = tr("Couldn't save the update download.");
            reply->abort();
            return;
        }
        m_packageHash.addData(chunk);
    };
    connect(reply, &QNetworkReply::readyRead, this, consume);
    connect(reply, &QNetworkReply::downloadProgress, this, [this, reply](qint64 received, qint64 total) {
        m_downloadProgress = total > 0 ? double(received) / total : -1;
        if (total > qint64(2) * 1024 * 1024 * 1024) reply->abort();
        emit changed();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, checksum, consume] {
        reply->deleteLater();
        if (m_downloadReply != reply) return;
        m_downloadReply = nullptr;
        consume();
        const bool flushed = m_package.flush();
        m_package.close();
        if (reply->error() != QNetworkReply::NoError || !m_installError.isEmpty() || !flushed) {
            finishInstallation(m_installError.isEmpty() ? tr("Couldn't download the update: %1").arg(reply->errorString()) : m_installError);
            return;
        }
        if (m_packageHash.result() != checksum) {
            finishInstallation(tr("The update checksum did not match. Please try again."));
            return;
        }
        m_installStatus = tr("Installing update. Complete the administrator authentication prompt…");
        m_downloadProgress = -1;
        m_installer = new QProcess(this);
        emit changed();
        m_installer->setProcessChannelMode(QProcess::MergedChannels);
        connect(m_installer, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) finishInstallation(tr("Couldn't start the package installer."));
        });
        connect(m_installer, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
            if (code == 0 && status == QProcess::NormalExit) finishInstallation();
            else if (code == 126) finishInstallation(tr("Update installation was cancelled."));
            else finishInstallation(tr("Couldn't install the update: %1").arg(QString::fromUtf8(m_installer->readAll()).right(2000)));
        });
        auto arguments = m_installCommand.mid(1);
        arguments.append(m_package.fileName());
        m_installer->start(m_installCommand.first(), arguments);
    });
}

void UpdateChecker::finishInstallation(const QString &error)
{
    if (!m_installing) return;
    m_installing = false;
    m_installed = error.isEmpty();
    m_installError = error;
    m_installStatus = m_installed ? tr("Update installed. Restart ReSketch to finish.") : QString();
    if (m_installed) {
        m_settings.setValue("updates/completedVersion", m_available.value("version"));
        m_settings.setValue("updates/completedChangelog", m_available.value("changelog"));
        m_settings.sync();
    }
    m_package.close();
    m_downloadDirectory.reset();
    if (m_installer) { m_installer->deleteLater(); m_installer = nullptr; }
    emit changed();
    if (m_installed) emit installationComplete();
}

void UpdateChecker::cancelDownload()
{
    if (!m_installing || !m_downloadReply) return;
    const auto reply = m_downloadReply;
    m_downloadReply = nullptr;
    reply->abort();
    finishInstallation(tr("Update download was cancelled."));
}

void UpdateChecker::finishUpdate()
{
    if (!m_installed) return;
    // Wait for this process to exit before launching the installed CEF version.
    const bool started = QProcess::startDetached("/bin/sh", {"-c",
        "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; exec /usr/bin/resketch",
        "resketch-update-restart", QString::number(QCoreApplication::applicationPid())});
    if (started) QCoreApplication::quit();
    else { m_installError = tr("Couldn't restart ReSketch. Close and reopen it to finish updating."); emit changed(); }
}

#else
// System-managed builds expose the page state without compiling update operations.
UpdateChecker::UpdateChecker(QObject *parent, const QString &version, const QUrl &apiRoot, const QUrl &assetRoot)
    : QObject(parent), m_settings(QStringLiteral("aether64"), QStringLiteral("ReSketch")),
      m_network(this), m_version(version), m_apiRoot(apiRoot), m_assetRoot(assetRoot)
{
    QFile notes(QStringLiteral(":/CHANGELOG.txt"));
    m_currentChangelog = notes.open(QIODevice::ReadOnly) ? QString::fromUtf8(notes.readAll())
        : tr("No changelog was provided for this version.");
}
void UpdateChecker::cancelDownload() {}
void UpdateChecker::finishUpdate() {}
bool UpdateChecker::canMigrate() const { return false; }
void UpdateChecker::migrateToMain() {}
#endif
