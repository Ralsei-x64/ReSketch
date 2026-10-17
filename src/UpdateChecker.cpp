// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "UpdateChecker.h"
#ifndef RESKETCH_DISABLE_UPDATES
#include <QDesktopServices>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QUrlQuery>
#include <QVersionNumber>
#include <QSysInfo>
#include <QDir>
#include <chrono>

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

UpdateChecker::UpdateChecker(QObject *parent, const QString &version, const QUrl &apiRoot, const QUrl &assetRoot)
    : QObject(parent), m_settings(QStringLiteral("aether64"), QStringLiteral("ReSketch")),
      m_network(this), m_version(version), m_apiRoot(apiRoot), m_assetRoot(assetRoot)
{
    m_settings.remove("updates/branch"); // This build only accepts CEF releases.
    m_periodicTimer.setInterval(std::chrono::hours(5));
    m_periodicTimer.setTimerType(Qt::VeryCoarseTimer);
    connect(&m_periodicTimer, &QTimer::timeout, this, [this] {
        if (periodicEnabled()) check(Trigger::Periodic);
    });
    if (periodicEnabled()) m_periodicTimer.start();
    QFile notes(QStringLiteral(":/CHANGELOG.txt"));
    if (notes.open(QIODevice::ReadOnly))
        m_currentChangelog = releaseNotes(QString::fromUtf8(notes.readAll()), QVersionNumber::fromString(m_version));
    if (m_currentChangelog.isEmpty()) m_currentChangelog = tr("No changelog was provided for this version.");
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this] {
        // Let an authenticated package transaction finish if the app is closed.
        if (m_installer && m_installer->state() != QProcess::NotRunning) m_installer->waitForFinished(-1);
    });
}

bool UpdateChecker::enabled() const { return m_settings.value("updates/startup", true).toBool(); }
bool UpdateChecker::periodicEnabled() const { return m_settings.value("updates/periodic", true).toBool(); }
QString UpdateChecker::branch() const { return QStringLiteral("main"); }

void UpdateChecker::setEnabled(bool value)
{
    if (enabled() == value) return;
    m_settings.setValue("updates/startup", value);
    if (!value && m_checking && m_trigger == Trigger::Startup) cancel();
    emit changed();
}

void UpdateChecker::setPeriodicEnabled(bool value)
{
    if (periodicEnabled() == value) return;
    m_settings.setValue("updates/periodic", value);
    if (value) m_periodicTimer.start();
    else {
        m_periodicTimer.stop();
        if (m_checking && m_trigger == Trigger::Periodic) cancel();
    }
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
    if (m_installing) return;
    if (!m_installed) cancel();
    m_settings.remove("updates");
    m_periodicTimer.start();
    emit changed();
}

void UpdateChecker::checkAtStartup()
{
    if (m_startupAttempted || !enabled()) return;
    m_startupAttempted = true;
    check(Trigger::Startup);
}

void UpdateChecker::checkForUpdates()
{
    m_startupAttempted = true; // A manual check also satisfies this launch's startup check.
    check(Trigger::Manual);
}

void UpdateChecker::check(Trigger trigger)
{
    if (m_checking || m_installing || m_installed) return;
    cancel();
    m_trigger = trigger;
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
        const QString prefix = "cef";
        const QRegularExpression tagPattern("^" + prefix + "-v([0-9]+\\.[0-9]+\\.[0-9]+)-[0-9a-f]{7,40}$");
        QVersionNumber newest;
        bool foundBranch = false;
        for (const auto &value : document.array()) {
            const auto release = value.toObject();
            const auto tag = release.value("tag_name").toString();
            const auto match = tagPattern.match(tag);
            if (!match.hasMatch() || release.value("draft").toBool()) continue;
            foundBranch = true;
            const auto version = QVersionNumber::fromString(match.captured(1));
            if (version.segmentCount() != 3 || version <= QVersionNumber::fromString(m_version) || version <= newest) continue;
            newest = version;
            m_available = {{"version", match.captured(1)}, {"branch", branch()}, {"tag", tag},
                           {"url", "https://github.com/Ralsei-x64/ReSketch/releases/tag/" + tag},
                           {"changelog", release.value("body").toString().trimmed()}};
            const QString package = "resketch-" + prefix + "-" + match.captured(1) + "-"
                + tag.section('-', -1) + "-x86_64.pkg.tar.zst";
            bool hasPackage = false, hasChecksums = false;
            for (const auto &asset : release.value("assets").toArray()) {
                const QString name = asset.toObject().value("name").toString();
                hasPackage |= name == package;
                hasChecksums |= name == "SHA256SUMS";
            }
            if (hasPackage && hasChecksums) m_available["package"] = package;
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
    if (m_trigger != Trigger::Manual && !m_promptDismissed && !m_available.isEmpty()
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

bool UpdateChecker::canInstall() const
{
    return !m_checking && !m_installing && !m_installed && m_available.contains("package")
        && QSysInfo::currentCpuArchitecture() == "x86_64"
        && QFile::exists(m_installCommand.value(0)) && QFile::exists("/usr/bin/pacman");
}

void UpdateChecker::installUpdate()
{
    if (!canInstall()) return;
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
    // Wait for CEF's profile lock to be released before launching the new build.
    const bool started = QProcess::startDetached("/bin/sh", {"-c",
        "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; exec /usr/bin/resketch",
        "resketch-update-restart", QString::number(QCoreApplication::applicationPid())});
    if (started) QCoreApplication::quit();
    else { m_installError = tr("Couldn't restart ReSketch. Close and reopen it to finish updating."); emit changed(); }
}

QVariantMap UpdateChecker::completedUpdate() const
{
    const auto version = m_settings.value("updates/completedVersion").toString();
    if (m_installed || version.isEmpty() || QVersionNumber::fromString(m_version) < QVersionNumber::fromString(version)) return {};
    return {{"version", m_version}, {"changelog", m_currentChangelog.startsWith(m_version + " -")
        ? m_currentChangelog : m_settings.value("updates/completedChangelog").toString()}};
}

void UpdateChecker::dismissCompletedUpdate()
{
    m_settings.remove("updates/completedVersion");
    m_settings.remove("updates/completedChangelog");
    m_settings.sync();
    emit changed();
}

#else
// System-managed builds expose the page state without compiling update operations.
UpdateChecker::UpdateChecker(QObject *parent, const QString &version, const QUrl &apiRoot, const QUrl &assetRoot)
    : QObject(parent), m_settings(QStringLiteral("aether64"), QStringLiteral("ReSketch")),
      m_network(this), m_version(version), m_apiRoot(apiRoot), m_assetRoot(assetRoot)
{
}
void UpdateChecker::cancelDownload() {}
void UpdateChecker::finishUpdate() {}
bool UpdateChecker::enabled() const { return false; }
bool UpdateChecker::periodicEnabled() const { return false; }
QString UpdateChecker::branch() const { return QStringLiteral("main"); }
bool UpdateChecker::canInstall() const { return false; }
QVariantMap UpdateChecker::completedUpdate() const { return {}; }
void UpdateChecker::setEnabled(bool) {}
void UpdateChecker::setPeriodicEnabled(bool) {}
void UpdateChecker::checkAtStartup() {}
void UpdateChecker::checkForUpdates() {}
void UpdateChecker::skipUpdate() {}
void UpdateChecker::openRelease() const {}
void UpdateChecker::installUpdate() {}
void UpdateChecker::dismissCompletedUpdate() {}
void UpdateChecker::reset() {}
#endif
