// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "ExtensionManager.h"
#include "CefApp.h"
#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_parser.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/views/cef_fill_layout.h"
#include "include/views/cef_window_delegate.h"
#include <QCryptographicHash>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
#include <QPointer>
#include <QNetworkReply>
#include <QSet>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QtEndian>
#include <archive.h>
#include <archive_entry.h>
#include <memory>
#include <utility>

// Chrome's extension management WebUI requires Chrome style, while document
// canvases use Alloy OSR. Load the management page only for custom extension changes.
class ExtensionControl final : public CefClient, public CefLifeSpanHandler, public CefLoadHandler,
    public CefDevToolsMessageObserver, public CefWindowDelegate {
public:
    CefRefPtr<CefBrowserView> view;
    CefRefPtr<CefWindow> window;
    CefRefPtr<CefBrowser> browser;
    CefRefPtr<CefRegistration> observer;
    std::function<void()> ready;
    std::function<void(int, bool, QJsonObject)> result;
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    void start() {
        view = CefBrowserView::CreateBrowserView(this, "chrome://extensions/", CefBrowserSettings(), nullptr, CefRequestContext::GetGlobalContext(), nullptr);
        CefWindow::CreateTopLevelWindow(this);
    }
    void OnWindowCreated(CefRefPtr<CefWindow> value) override {
        window = value; window->SetToFillLayout(); window->AddChildView(view); window->SetSize(CefSize(800, 600));
        // Deliberately never Show(): extension interaction uses our QML panels.
    }
    void OnWindowDestroyed(CefRefPtr<CefWindow>) override { window = nullptr; }
    void OnAfterCreated(CefRefPtr<CefBrowser> value) override {
        browser = value; ReSketchCef::browserCreated(browser); observer = browser->GetHost()->AddDevToolsMessageObserver(this);
    }
    void OnBeforeClose(CefRefPtr<CefBrowser> value) override {
        ReSketchCef::browserClosed(value->GetIdentifier()); observer = nullptr; browser = nullptr; view = nullptr;
    }
    void OnLoadEnd(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, int) override {
        if (frame->IsMain() && frame->GetURL() == "chrome://extensions/" && ready) ready();
    }
    void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int id, bool ok, const void *data, size_t size) override {
        if (result) result(id, ok, QJsonDocument::fromJson(QByteArray(static_cast<const char *>(data), size)).object());
    }
private:
    IMPLEMENT_REFCOUNTING(ExtensionControl);
};

namespace {
// chrome.tabs.create/openOptionsPage create Chrome-style browsers without a
// source CefView. Redirect those through the same QML window as popup links.
class ExtensionPageClient final : public CefClient, public CefLifeSpanHandler, public CefRequestHandler {
public:
    std::function<void(QUrl)> open;
    bool redirected = false;
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        ReSketchCef::browserCreated(browser);
        if (auto view = CefBrowserView::GetForBrowser(browser))
            if (auto window = view->GetWindow()) window->Hide();
    }
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        ReSketchCef::browserClosed(browser->GetIdentifier());
    }
    bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefRequest> request, bool, bool) override {
        if (!frame->IsMain()) return false;
        const QUrl url(QString::fromStdString(request->GetURL().ToString()));
        if (url.isEmpty() || url == QUrl("about:blank")) return false;
        if (!redirected) {
            redirected = true;
            QTimer::singleShot(0, qApp, [browser, url, callback = open] {
                if (callback && (url.scheme() == "https" || url.scheme() == "http" || url.scheme() == "chrome-extension")) callback(url);
                browser->GetHost()->CloseBrowser(true);
            });
        }
        return true;
    }
private:
    IMPLEMENT_REFCOUNTING(ExtensionPageClient);
};
constexpr qint64 MaxPackage = 64 * 1024 * 1024, MaxExpanded = 128 * 1024 * 1024;
QString safePage(const QJsonValue &value) {
    const auto path = value.toString();
    if (path.isEmpty() || path.startsWith('/') || path.contains('\\') || path.contains(':')
        || path.split('/').contains("..") || path.contains('?') || path.contains('#')) return {};
    return path;
}
QString extensionName(const QString &directory, const QJsonObject &manifest) {
    const auto name = manifest.value("name").toString();
    if (!name.startsWith("__MSG_") || !name.endsWith("__")) return name;
    const auto key = name.mid(6, name.size() - 8);
    QStringList locales;
    for (auto language : QLocale::system().uiLanguages()) {
        language.replace('-', '_');
        locales << language << language.section('_', 0, 0);
    }
    locales << manifest.value("default_locale").toString();
    locales.removeDuplicates();
    for (const auto &locale : locales) {
        if (locale.isEmpty() || locale.contains('/') || locale.contains('\\') || locale.contains("..")) continue;
        QFile file(directory + "/_locales/" + locale + "/messages.json");
        if (!file.open(QIODevice::ReadOnly) || file.size() > 1024 * 1024) continue;
        const auto messages = QJsonDocument::fromJson(file.readAll()).object();
        for (auto it = messages.begin(); it != messages.end(); ++it) {
            if (it.key().compare(key, Qt::CaseInsensitive) != 0) continue;
            const auto message = it.value().toObject().value("message").toString();
            if (!message.isEmpty() && message.size() <= 256) return message;
        }
    }
    return name;
}
}
ExtensionManager::ExtensionManager(QObject *parent, bool available)
    : QObject(parent), m_available(available) {
    m_extensions = m_settings.value("extensions/packages").toList();
    // Resolve names again for packages installed before localization support.
    for (auto &entry : m_extensions) {
        auto row = entry.toMap();
        const auto key = row.value("key").toString();
        if (key.size() != 64 || key.contains('/') || key.contains('\\') || key.contains("..")) continue;
        const auto directory = root() + '/' + key;
        QFile file(directory + "/manifest.json");
        if (!file.open(QIODevice::ReadOnly) || file.size() > 1024 * 1024) continue;
        const auto name = extensionName(directory, QJsonDocument::fromJson(file.readAll()).object());
        if (!name.isEmpty()) { row["name"] = name; entry = row; }
    }
    m_socket.setMaxAllowedIncomingMessageSize(1024 * 1024);
    connect(&m_socket, &QWebSocket::connected, this, [this] {
        m_connecting = false; m_error.clear(); m_failures.clear(); m_busy = true;
        command("Extensions.getExtensions", {}, [this](QJsonObject response) {
            if (response.contains("error")) { m_busy = false; m_error = response.value("error").toObject().value("message").toString(); emit changed(); return; }
            for (const auto &value : response.value("result").toObject().value("extensions").toArray()) {
                const auto row = value.toObject(); const auto path = row.value("path").toString();
                for (const auto &item : m_extensions) { const auto key = item.toMap().value("key").toString();
                    if (path == root() + '/' + key) { m_loaded[key] = row.value("id").toString(); if (row.value("enabled").toBool()) m_enabled.insert(key); } }
            }
            ReSketchCef::defaultClientFactory = [manager = QPointer<ExtensionManager>(this)]() -> CefRefPtr<CefClient> {
                auto client = CefRefPtr<ExtensionPageClient>(new ExtensionPageClient);
                client->open = [manager](const QUrl &url) {
                    if (!manager || !manager->available()) return;
                    emit manager->pageRequested(url, manager->m_loaded.key(url.host()));
                };
                return client;
            };
            m_busy = false; reconcile(); emit changed();
        });
    });
    connect(&m_socket, &QWebSocket::textMessageReceived, this, [this](const QString &message) {
        const auto data = QJsonDocument::fromJson(message.toUtf8()).object();
        if (auto callback = m_callbacks.take(data.value("id").toInt())) callback(data);
    });
    connect(&m_socket, &QWebSocket::disconnected, this, [this] {
        m_connecting = false; m_busy = false; releaseControl(); m_loaded.clear(); m_enabled.clear();
        const auto callbacks = std::exchange(m_callbacks, {});
        for (const auto &callback : callbacks) callback({{"error", QJsonObject{{"message", "Extension connection closed"}}}});
        emit changed();
    });
    connect(&m_socket, &QWebSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        m_connecting = false; m_error = m_socket.errorString(); emit changed();
    });
    m_retry.setInterval(2000);
    connect(&m_retry, &QTimer::timeout, this, &ExtensionManager::connectBrowser);
    if (m_available) { m_retry.start(); QTimer::singleShot(0, this, &ExtensionManager::connectBrowser); }
}
ExtensionManager::~ExtensionManager() { shutdown(); }
void ExtensionManager::shutdown() {
    m_available = false; m_retry.stop(); m_socket.disconnect(this); m_socket.abort();
    for (auto *reply : m_network.findChildren<QNetworkReply *>()) { reply->disconnect(this); reply->abort(); }
    m_callbacks.clear(); m_enabled.clear();
    releaseControl();
}
void ExtensionManager::releaseControl() {
    m_managementReady = false;
    if (!m_control) return;
    m_control->ready = {}; m_control->result = {};
    if (m_control->window) m_control->window->Close();
    m_control = nullptr;
}
void ExtensionManager::parkControl() {
    m_managementReady = false;
    // Closing the last Chrome-style host tears down extension APIs used by Alloy popups.
    // Keep its profile alive on a blank page, with no extension-management scripts running.
    if (m_control && m_control->browser && m_control->browser->GetMainFrame()->GetURL() != "about:blank")
        m_control->browser->GetMainFrame()->LoadURL("about:blank");
}
QString ExtensionManager::root() const { return QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + "/extensions"; }
QVariantList ExtensionManager::extensions() const {
    auto list = m_extensions;
    for (auto &entry : list) {
        auto row = entry.toMap(); row["loaded"] = m_enabled.contains(row.value("key").toString()); row["error"] = m_failures.value(row.value("key").toString()); entry = row;
    }
    return list;
}
void ExtensionManager::save() { m_settings.setValue("extensions/packages", m_extensions); emit changed(); }
void ExtensionManager::connectBrowser() {
    if (!m_available || m_connecting || m_socket.state() != QAbstractSocket::UnconnectedState || !ReSketchCef::initialized()
        || (m_extensions.isEmpty() && m_loaded.isEmpty())) return;
    m_connecting = true;
    QNetworkRequest request(QUrl(QString("http://127.0.0.1:%1/json/version").arg(ReSketchCef::debuggingPort())));
    request.setTransferTimeout(3000);
    auto *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const auto endpoint = QUrl(QJsonDocument::fromJson(reply->readAll()).object().value("webSocketDebuggerUrl").toString());
        const bool valid = reply->error() == QNetworkReply::NoError && endpoint.scheme() == "ws" && endpoint.host() == "127.0.0.1"
            && endpoint.port() == ReSketchCef::debuggingPort();
        reply->deleteLater();
        if (!valid || !m_available) { m_connecting = false; return; }
        QNetworkRequest request(endpoint); request.setRawHeader("Origin", "devtools://devtools");
        m_socket.open(request);
    });
}
void ExtensionManager::command(const QString &method, QJsonObject params, Callback callback) {
    const int id = ++m_serial;
    m_callbacks[id] = std::move(callback);
    QJsonObject request{{"id",id},{"method",method},{"params",params}};
    if (method == "Runtime.evaluate") {
        const auto json = QJsonDocument(params).toJson(QJsonDocument::Compact).toStdString();
        const auto value = CefParseJSON(json, JSON_PARSER_RFC);
        if (!m_control || !m_control->browser || !m_control->browser->GetHost()->ExecuteDevToolsMethod(id, method.toStdString(), value->GetDictionary())) {
            if (auto pending = m_callbacks.take(id)) pending({{"error",QJsonObject{{"message","Extension manager is unavailable"}}}});
        }
    } else m_socket.sendTextMessage(QString::fromUtf8(QJsonDocument(request).toJson(QJsonDocument::Compact)));
    QTimer::singleShot(10000, this, [this, id] {
        if (auto callback = m_callbacks.take(id)) callback({{"error", QJsonObject{{"message", "Extension operation timed out"}}}});
    });
}
void ExtensionManager::reconcile() {
    if (!m_available || m_busy || m_socket.state() != QAbstractSocket::ConnectedState) return;
    QMap<QString, QString> wanted; QSet<QString> enabled;
    for (const auto &entry : m_extensions) {
        const auto row = entry.toMap(); const auto key = row.value("key").toString();
        if (key.size() != 64 || key.contains('/')) continue;
        if (row.value("enabled").toBool() || m_loaded.contains(key)) wanted[key] = root() + "/" + key;
        if (row.value("enabled").toBool()) enabled.insert(key);
    }
    QString key, method; QJsonObject args;
    for (auto it = m_loaded.begin(); it != m_loaded.end(); ++it) if (!wanted.contains(it.key())) {
        key = it.key(); method = "Extensions.uninstall"; args = {{"id",it.value()}}; break;
    }
    if (method.isEmpty()) for (auto it = wanted.begin(); it != wanted.end(); ++it) if (!m_loaded.contains(it.key()) && !m_failures.contains(it.key())) {
        key = it.key(); method = "Extensions.loadUnpacked"; args = {{"path",it.value()},{"enableInIncognito",true}}; break;
    }
    if (method.isEmpty()) for (auto it = m_loaded.begin(); it != m_loaded.end(); ++it)
        if (wanted.contains(it.key()) && !m_failures.contains(it.key()) && enabled.contains(it.key()) != m_enabled.contains(it.key())) {
            key = it.key(); method = "Runtime.evaluate";
            const auto values = QString::fromUtf8(QJsonDocument(QJsonArray{it.value(),enabled.contains(key)}).toJson(QJsonDocument::Compact)).mid(1).chopped(1);
            args = {{"expression", "new Promise((resolve,reject)=>chrome.management.setEnabled(" + values + ",()=>chrome.runtime.lastError?reject(Error(chrome.runtime.lastError.message)):resolve(true)))"},
                {"awaitPromise",true},{"returnByValue",true}};
            break;
        }
    if (method.isEmpty()) { parkControl(); emit changed(); return; }
    if (method == "Runtime.evaluate" && !m_managementReady) {
        m_busy = true;
        if (m_control && m_control->browser) {
            m_control->browser->GetMainFrame()->LoadURL("chrome://extensions/");
            return;
        }
        m_control = new ExtensionControl;
        m_control->ready = [this] { m_managementReady = true; m_busy = false; reconcile(); emit changed(); };
        m_control->result = [this](int id, bool ok, QJsonObject value) {
            if (auto callback = m_callbacks.take(id)) callback({{ok ? "result" : "error",value}});
        };
        m_control->start();
        return;
    }
    m_busy = true; emit changed();
    const auto complete = [this, key, method, enable = enabled.contains(key)](QJsonObject response) {
        m_busy = false;
        const auto runtime = response.value("result").toObject();
        if (response.contains("error") || runtime.contains("exceptionDetails")) {
            m_error = response.value("error").toObject().value("message").toString();
            if (m_error.isEmpty()) m_error = runtime.value("exceptionDetails").toObject().value("exception").toObject().value("description").toString(tr("Extension operation failed."));
            m_failures[key] = m_error; parkControl(); emit changed();
            if (method != "Extensions.uninstall") reconcile();
            return;
        }
        m_error.clear();
        if (method == "Extensions.uninstall") {
            m_loaded.remove(key); m_enabled.remove(key);
            if (key.size() == 64 && !key.contains('/')) QDir(root() + '/' + key).removeRecursively();
        } else if (method == "Extensions.loadUnpacked") {
            m_loaded[key] = runtime.value("id").toString(); m_enabled.insert(key);
        } else {
            if (enable) m_enabled.insert(key); else m_enabled.remove(key);
        }
        emit changed(); reconcile();
    };
    command(method, args, complete);
}
void ExtensionManager::choosePackage() {
    if (!m_available) return;
    const auto file = QFileDialog::getOpenFileName(nullptr, tr("Load Chrome extension"), {}, tr("Chrome extensions (*.crx)"));
    if (!file.isEmpty()) installPackage(file);
}
bool ExtensionManager::installPackage(const QString &path) {
    const auto fail = [this](const QString &error) { m_error = error; emit changed(); return false; };
    if (!m_available) return fail(tr("Extensions are disabled in Safe Mode."));
    QFile file(path);
    if (!path.endsWith(".crx", Qt::CaseInsensitive) || !file.open(QIODevice::ReadOnly) || file.size() > MaxPackage)
        return fail(tr("Choose a .crx file smaller than 64 MiB."));
    const auto bytes = file.readAll();
    if (bytes.size() < 12 || bytes.left(4) != "Cr24") return fail(tr("Invalid CRX header."));
    const auto read = [&](int offset) { return qFromLittleEndian<quint32>(bytes.constData() + offset); };
    const auto version = read(4);
    quint64 offset = 0;
    if (version == 3) offset = 12ull + read(8);
    else if (version == 2 && bytes.size() >= 16) offset = 16ull + read(8) + read(12);
    else return fail(tr("Only CRX2 and CRX3 packages are supported."));
    if (offset >= quint64(bytes.size()) || bytes.mid(offset, 4) != QByteArray("PK\003\004", 4)) return fail(tr("Invalid CRX archive."));
    const QString key = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex();
    for (const auto &entry : m_extensions) if (entry.toMap().value("key") == key) return fail(tr("This extension is already installed."));
    if (m_extensions.size() >= 32) return fail(tr("Remove an extension before adding more (limit: 32)."));
    QDir().mkpath(root());
    QTemporaryDir staging(root() + "/import-XXXXXX");
    if (!staging.isValid()) return fail(tr("Cannot create extension directory."));
    std::unique_ptr<archive, decltype(&archive_read_free)> archive(archive_read_new(), archive_read_free);
    archive_read_support_format_zip(archive.get());
    if (archive_read_open_memory(archive.get(), bytes.constData() + offset, bytes.size() - offset) != ARCHIVE_OK) return fail(tr("Cannot read extension archive."));
    archive_entry *entry = nullptr; qint64 total = 0; int count = 0, status; QSet<QString> paths;
    while ((status = archive_read_next_header(archive.get(), &entry)) == ARCHIVE_OK) {
        const QString name = QString::fromUtf8(archive_entry_pathname(entry));
        const QString clean = QDir::cleanPath(name);
        const auto type = archive_entry_filetype(entry);
        if (++count > 5000 || name.isEmpty() || name.contains('\\') || name.contains(':') || QDir::isAbsolutePath(name)
            || name.split('/').contains("..") || clean == "." || paths.contains(clean) || archive_entry_symlink(entry) || archive_entry_hardlink(entry)
            || (type != AE_IFREG && type != AE_IFDIR) || archive_entry_is_encrypted(entry)) return fail(tr("Unsafe or unsupported extension archive entry."));
        paths.insert(clean);
        const QString destination = staging.path() + '/' + clean;
        if (type == AE_IFDIR) { if (!QDir().mkpath(destination)) return fail(tr("Cannot create extension directory.")); continue; }
        if (archive_entry_size(entry) < 0 || archive_entry_size(entry) > MaxExpanded - total) return fail(tr("Extension expands beyond 128 MiB."));
        QDir().mkpath(QFileInfo(destination).absolutePath());
        QFile output(destination); if (!output.open(QIODevice::WriteOnly)) return fail(output.errorString());
        char buffer[65536]; la_ssize_t n;
        while ((n = archive_read_data(archive.get(), buffer, sizeof buffer)) > 0) {
            total += n;
            if (total > MaxExpanded || output.write(buffer, n) != n) return fail(tr("Cannot extract extension (size limit or write error)."));
        }
        if (n < 0) return fail(tr("Corrupt extension archive."));
    }
    if (status != ARCHIVE_EOF) return fail(tr("Corrupt extension archive."));
    QFile manifestFile(staging.path() + "/manifest.json");
    if (!manifestFile.open(QIODevice::ReadOnly) || manifestFile.size() > 1024 * 1024) return fail(tr("Missing or oversized extension manifest."));
    const auto manifest = QJsonDocument::fromJson(manifestFile.readAll()).object();
    if (manifest.value("manifest_version").toInt() != 3 || manifest.value("name").toString().isEmpty() || manifest.value("name").toString().size() > 256
        || manifest.value("version").toString().isEmpty() || manifest.value("version").toString().size() > 100)
        return fail(tr("This Chromium version requires a Manifest V3 extension with a name and version."));
    const QString destination = root() + '/' + key;
    if (QFileInfo::exists(destination)) QDir(destination).removeRecursively();
    if (!QDir().rename(staging.path(), destination)) return fail(tr("Cannot save extension."));
    QStringList permissions;
    for (const auto &permission : manifest.value("permissions").toArray()) permissions << permission.toString();
    for (const auto &permission : manifest.value("host_permissions").toArray()) permissions << permission.toString();
    for (const auto &script : manifest.value("content_scripts").toArray())
        for (const auto &match : script.toObject().value("matches").toArray()) if (!permissions.contains(match.toString())) permissions << match.toString();
    const auto options = manifest.value("options_page").isString() ? manifest.value("options_page") : manifest.value("options_ui").toObject().value("page");
    const auto icons = manifest.value("icons").toObject();
    QString icon; int iconSize = 0;
    for (auto it = icons.begin(); it != icons.end(); ++it) if (it.key().toInt() >= iconSize && !safePage(it.value()).isEmpty()) {
        iconSize = it.key().toInt(); icon = safePage(it.value());
    }
    const auto iconUrl = !icon.isEmpty() && QFileInfo(destination + '/' + icon).isFile() ? QUrl::fromLocalFile(destination + '/' + icon) : QUrl();
    m_extensions.append(QVariantMap{{"key",key},{"name",extensionName(destination, manifest)},{"version",manifest.value("version").toString()},
        {"enabled",true},{"permissions",permissions},{"icon",iconUrl.toString()},{"popup",safePage(manifest.value("action").toObject().value("default_popup"))},{"options",safePage(options)}});
    m_error.clear(); save(); reconcile(); connectBrowser(); return true;
}
void ExtensionManager::setExtensionEnabled(const QString &key, bool enabled) {
    for (auto &entry : m_extensions) { auto row = entry.toMap(); if (row.value("key") == key) { m_failures.remove(key); row["enabled"] = enabled; entry = row; save(); reconcile(); return; } }
}
void ExtensionManager::removeExtension(const QString &key) {
    for (qsizetype i = 0; i < m_extensions.size(); ++i) if (m_extensions[i].toMap().value("key") == key) {
        const bool installed = m_loaded.contains(key);
        m_extensions.removeAt(i); m_failures.remove(key); save();
        if (!installed && key.size() == 64 && !key.contains('/')) QDir(root() + '/' + key).removeRecursively();
        reconcile(); return;
    }
}
QUrl ExtensionManager::extensionPage(const QString &key, bool options) const {
    if (!m_available || !m_enabled.contains(key)) return {};
    for (const auto &entry : m_extensions) {
        const auto row = entry.toMap();
        if (row.value("key") == key && row.value("enabled").toBool()) {
            const auto page = row.value(options ? "options" : "popup").toString();
            if (!page.isEmpty()) return QUrl("chrome-extension://" + m_loaded[key] + '/' + page);
        }
    }
    return {};
}
