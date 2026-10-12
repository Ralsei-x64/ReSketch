// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

#include <QApplication>
#include <QClipboard>
#include <QColorDialog>
#include <QCursor>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QEvent>
#include <QEventLoop>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QIcon>
#include <QJSValue>
#include <QLocalServer>
#include <QLocalSocket>
#include <QMap>
#include <QPalette>
#include <QPointer>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QSGRendererInterface>
#include <QStandardPaths>
#include <QStyleHints>
#include <QTimer>
#include <QVariantMap>
#include <QWindow>
#include <QWidget>
#include "FontHelper.h"
#include <KWindowEffects>
#include <KNotification>
#include <QWebEngineNotification>
#include <algorithm>
#include <cstdio>
#include <memory>
#include <optional>
#ifdef Q_OS_LINUX
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>
#endif
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#if QT_CONFIG(vulkan)
#include <QVulkanFunctions>
#include <QVulkanInstance>
#endif

static std::optional<bool> heldAltKey()
{
#ifdef Q_OS_LINUX
    // logind grants the active desktop user access to input devices. Query only
    // Alt's current state; no event capture or elevated permissions are needed.
    bool keyboardReadable = false;
    const QDir input(QStringLiteral("/dev/input"));
    for (const QString &name : input.entryList({QStringLiteral("event*")}, QDir::System | QDir::Files)) {
        const int device = ::open(QFile::encodeName(input.filePath(name)).constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (device < 0) continue;
        unsigned char keys[(KEY_MAX + 8) / 8]{};
        const auto pressed = [&keys](int key) { return keys[key / 8] & (1 << (key % 8)); };
        const bool keyboard = ::ioctl(device, EVIOCGBIT(EV_KEY, sizeof(keys)), keys) >= 0
                              && (pressed(KEY_LEFTALT) || pressed(KEY_RIGHTALT));
        std::fill(std::begin(keys), std::end(keys), 0);
        const bool readable = keyboard && ::ioctl(device, EVIOCGKEY(sizeof(keys)), keys) >= 0;
        ::close(device);
        if (readable && (pressed(KEY_LEFTALT) || pressed(KEY_RIGHTALT))) return true;
        keyboardReadable |= readable;
    }
    if (keyboardReadable) return false;
#endif
    return std::nullopt;
}

static bool requestedSafeMode(const QStringList &arguments)
{
    if (arguments.contains(QStringLiteral("--safe-mode"))
        || QGuiApplication::queryKeyboardModifiers().testFlag(Qt::AltModifier))
        return true;
    if (const auto alt = heldAltKey(); alt.has_value())
        return *alt;
    if (!QGuiApplication::platformName().startsWith(QStringLiteral("wayland")))
        return false;

    // Wayland delivers held modifiers only after a window receives keyboard focus.
    // Use an invisible raster focus window before creating rendering surfaces.
    QWidget startup(nullptr, Qt::Tool | Qt::FramelessWindowHint);
    startup.setAttribute(Qt::WA_TranslucentBackground);
    startup.setWindowOpacity(0);
    startup.resize(1, 1);
    const bool quitOnClose = QGuiApplication::quitOnLastWindowClosed();
    QGuiApplication::setQuitOnLastWindowClosed(false);
    startup.show();
    startup.activateWindow();
    bool safeMode = false;
    QEventLoop loop;
    QTimer poll;
    QObject::connect(&poll, &QTimer::timeout, &loop, [&] {
        if (QGuiApplication::queryKeyboardModifiers().testFlag(Qt::AltModifier)) {
            safeMode = true;
            loop.quit();
        }
    });
    poll.start(10);
    QTimer::singleShot(250, &loop, &QEventLoop::quit);
    loop.exec();
    startup.hide();
    QGuiApplication::setQuitOnLastWindowClosed(quitOnClose);
    return safeMode;
}

static bool isSoftwareRenderer(const QString &name)
{
    static const QRegularExpression software(QStringLiteral("llvmpipe|softpipe|swrast|swiftshader|software|lavapipe"),
                                              QRegularExpression::CaseInsensitiveOption);
    return software.match(name).hasMatch();
}

static bool hasGraphicsAcceleration(QQuickWindow *window)
{
    auto *renderer = window->rendererInterface();
    switch (renderer->graphicsApi()) {
    case QSGRendererInterface::OpenGL: {
        auto *context = QOpenGLContext::currentContext();
        if (!context) return false;
        const auto *name = context->functions()->glGetString(GL_RENDERER);
        return name && *name && !isSoftwareRenderer(QString::fromLatin1(reinterpret_cast<const char *>(name)));
    }
#if QT_CONFIG(vulkan)
    case QSGRendererInterface::Vulkan: {
        auto *instance = static_cast<QVulkanInstance *>(renderer->getResource(window, QSGRendererInterface::VulkanInstanceResource));
        auto *device = static_cast<VkPhysicalDevice *>(renderer->getResource(window, QSGRendererInterface::PhysicalDeviceResource));
        if (!instance || !device || !*device) return false;
        VkPhysicalDeviceProperties properties{};
        instance->functions()->vkGetPhysicalDeviceProperties(*device, &properties);
        return properties.deviceType != VK_PHYSICAL_DEVICE_TYPE_CPU && properties.deviceName[0]
               && !isSoftwareRenderer(QString::fromUtf8(properties.deviceName));
    }
#endif
    default:
        return false;
    }
}

class AppSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY changed)
    Q_PROPERTY(bool darkTheme READ darkTheme NOTIFY effectiveThemeChanged)
    Q_PROPERTY(bool figmaSystemColors READ figmaSystemColors WRITE setFigmaSystemColors NOTIFY changed)
    Q_PROPERTY(bool figmaCustomCssEnabled READ figmaCustomCssEnabled WRITE setFigmaCustomCssEnabled NOTIFY changed)
    Q_PROPERTY(QString figmaCustomCss READ figmaCustomCss WRITE setFigmaCustomCss NOTIFY changed)
    Q_PROPERTY(QVariantMap figmaPalette READ figmaPalette NOTIFY effectiveThemeChanged)
    Q_PROPERTY(bool translucentSidebars READ translucentSidebars WRITE setTranslucentSidebars NOTIFY changed)
    Q_PROPERTY(QString sidebarBackdrop READ sidebarBackdrop WRITE setSidebarBackdrop NOTIFY changed)
    Q_PROPERTY(bool menuIntegration READ menuIntegration WRITE setMenuIntegration NOTIFY changed)
    Q_PROPERTY(bool reduceMotion READ reduceMotion WRITE setReduceMotion NOTIFY changed)
    Q_PROPERTY(int toolbarOpacity READ toolbarOpacity WRITE setToolbarOpacity NOTIFY changed)
    Q_PROPERTY(bool windowControlsInTabBar READ windowControlsInTabBar WRITE setWindowControlsInTabBar NOTIFY changed)
    Q_PROPERTY(bool keepWindowDecorations READ keepWindowDecorations WRITE setKeepWindowDecorations NOTIFY changed)
    Q_PROPERTY(bool ignoreToolbarBlur READ ignoreToolbarBlur WRITE setIgnoreToolbarBlur NOTIFY changed)
    Q_PROPERTY(int minimumLoadedTabs READ minimumLoadedTabs WRITE setMinimumLoadedTabs NOTIFY changed)
    Q_PROPERTY(int maximumLoadedTabs READ maximumLoadedTabs WRITE setMaximumLoadedTabs NOTIFY changed)
    Q_PROPERTY(int sleepMinutes READ sleepMinutes WRITE setSleepMinutes NOTIFY changed)
    Q_PROPERTY(bool sleepingTabPreviews READ sleepingTabPreviews WRITE setSleepingTabPreviews NOTIFY changed)
    Q_PROPERTY(bool keepHomeAwake READ keepHomeAwake WRITE setKeepHomeAwake NOTIFY changed)
    Q_PROPERTY(bool rememberOpenedTabs READ rememberOpenedTabs WRITE setRememberOpenedTabs NOTIFY changed)
    Q_PROPERTY(bool deferRestoredTabs READ deferRestoredTabs WRITE setDeferRestoredTabs NOTIFY changed)
    Q_PROPERTY(bool desktopNotifications READ desktopNotifications WRITE setDesktopNotifications NOTIFY changed)
    Q_PROPERTY(QStringList rememberedFileTabs READ rememberedFileTabs NOTIFY changed)
    Q_PROPERTY(QVariantList rememberedTabGroups READ rememberedTabGroups NOTIFY changed)
    Q_PROPERTY(bool releaseClosedWindows READ releaseClosedWindows WRITE setReleaseClosedWindows NOTIFY changed)
    Q_PROPERTY(bool cullOffscreenOverviewEffects READ cullOffscreenOverviewEffects WRITE setCullOffscreenOverviewEffects NOTIFY changed)
    Q_PROPERTY(bool compactPreviewTextures READ compactPreviewTextures WRITE setCompactPreviewTextures NOTIFY changed)
    Q_PROPERTY(int overviewPreviewQuality READ overviewPreviewQuality WRITE setOverviewPreviewQuality NOTIFY changed)
    Q_PROPERTY(bool gpuRasterization READ gpuRasterization WRITE setGpuRasterization NOTIFY changed)
    Q_PROPERTY(bool zeroCopyRasterization READ zeroCopyRasterization WRITE setZeroCopyRasterization NOTIFY changed)
    Q_PROPERTY(bool experimentalCanvasFeatures READ experimentalCanvasFeatures WRITE setExperimentalCanvasFeatures NOTIFY changed)
    Q_PROPERTY(bool useVulkan READ useVulkan WRITE setUseVulkan NOTIFY changed)
    Q_PROPERTY(QString chromiumFlags READ chromiumFlags WRITE setChromiumFlags NOTIFY changed)
    Q_PROPERTY(QString profileStoragePath READ profileStoragePath CONSTANT)
    Q_PROPERTY(QVariantList exportHistory READ exportHistory NOTIFY exportHistoryChanged)
    Q_PROPERTY(bool nativeTabDragSupported READ nativeTabDragSupported CONSTANT)
    Q_PROPERTY(QString gpuAccelerationWarning READ gpuAccelerationWarning NOTIFY gpuAccelerationWarningChanged)
    Q_PROPERTY(bool safeMode READ safeMode CONSTANT)

public:
    QString gpuAccelerationWarning() const { return graphicsWarning; }
    bool safeMode() const { return recoveryMode; }
    explicit AppSettings(QObject *parent = nullptr, bool safeMode = false)
        : QObject(parent), store(QStringLiteral("aether64"), QStringLiteral("ReSketch")), recoveryMode(safeMode)
    {
        applyTheme();
        connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, this,
                [this] { emit effectiveThemeChanged(); });
        qGuiApp->installEventFilter(this);
        connect(qGuiApp, &QCoreApplication::aboutToQuit, this, [this] { saveOpenedTabs(); });
    }

    QString theme() const { return store.value(QStringLiteral("theme"), QStringLiteral("auto")).toString(); }
    bool darkTheme() const
    {
        if (theme() == QStringLiteral("dark"))
            return true;
        if (theme() == QStringLiteral("light"))
            return false;
        const auto scheme = QGuiApplication::styleHints()->colorScheme();
        return scheme == Qt::ColorScheme::Dark
               || (scheme == Qt::ColorScheme::Unknown
                   && QGuiApplication::palette().color(QPalette::Window).lightness() < 128);
    }
    bool menuIntegration() const { return store.value(QStringLiteral("menuIntegration"), true).toBool(); }
    bool desktopNotifications() const { return !safeMode() && store.value(QStringLiteral("desktopNotifications"), true).toBool(); }
    void setDesktopNotifications(bool value)
    {
        store.setValue(QStringLiteral("desktopNotifications"), value);
        emit changed();
    }
    Q_INVOKABLE QColor chooseGroupColor(const QColor &initial, QObject *owner)
    {
        QColorDialog dialog(initial);
        dialog.setWindowTitle(tr("Tab group color"));
        dialog.setWindowModality(Qt::WindowModal);
        dialog.winId();
        if (auto *window = qobject_cast<QWindow *>(owner)) dialog.windowHandle()->setTransientParent(window);
        return dialog.exec() == QDialog::Accepted ? dialog.selectedColor() : initial;
    }
    KNotification *createFigmaNotification(const QString &title, const QString &text)
    {
        auto *notice = new KNotification(QStringLiteral("figmaNotification"), KNotification::CloseOnTimeout, this);
        notice->setComponentName(QStringLiteral("org.aether64.resketch"));
        notice->setTitle(title);
        notice->setText(text.toHtmlEscaped());
        notice->setIconName(QStringLiteral("org.aether64.resketch"));
        return notice;
    }
    Q_INVOKABLE void showHomeNotification(const QString &title, const QString &text, const QString &address, QObject *owner)
    {
        auto *window = qobject_cast<QWindow *>(owner);
        if (!desktopNotifications() || !window || title.trimmed().isEmpty()
            || window->property("primaryWindow").value<QObject *>()) return;
        auto *notice = createFigmaNotification(title.left(256), text.left(2000));
        const QUrl url(address);
        const QString link = url.isValid() && (url.scheme() == QStringLiteral("https") || url.scheme() == QStringLiteral("http"))
            ? address : QString{};
        connect(notice->addDefaultAction(tr("Open ReSketch")), &KNotificationAction::activated, notice,
                [window = QPointer<QWindow>(window), link] {
            if (!window) return;
            QMetaObject::invokeMethod(window, "openNotificationLink", Q_ARG(QVariant, link));
            window->raise();
            window->requestActivate();
        });
        notice->sendEvent();
    }
    Q_INVOKABLE void showDesktopNotification(QObject *object, QObject *owner)
    {
        auto *web = qobject_cast<QWebEngineNotification *>(object);
        if (!web) return;
        const auto host = web->origin().host();
        if (!desktopNotifications() || web->origin().scheme() != QStringLiteral("https")
            || (host != QStringLiteral("figma.com") && !host.endsWith(QStringLiteral(".figma.com")))) {
            web->close();
            return;
        }
        auto *notice = createFigmaNotification(web->title(), web->message());
        web->setParent(notice);
        QQmlEngine::setObjectOwnership(web, QQmlEngine::CppOwnership);
        connect(web, &QWebEngineNotification::closed, notice, &KNotification::close);
        connect(notice, &KNotification::closed, web, &QWebEngineNotification::close);
        connect(notice->addDefaultAction(tr("Open ReSketch")), &KNotificationAction::activated, web,
                [web, window = QPointer<QWindow>(qobject_cast<QWindow *>(owner))] {
            if (window) {
                QMetaObject::invokeMethod(window, "activateHome", Q_ARG(QVariant, false));
                window->raise();
                window->requestActivate();
            }
            web->click();
        });
        notice->sendEvent();
        web->show();
    }
    bool rememberOpenedTabs() const { return store.value(QStringLiteral("rememberOpenedTabs"), false).toBool(); }
    bool deferRestoredTabs() const { return store.value(QStringLiteral("deferRestoredTabs"), true).toBool(); }
    void setDeferRestoredTabs(bool value)
    {
        if (deferRestoredTabs() == value) return;
        store.setValue(QStringLiteral("deferRestoredTabs"), value);
        emit changed();
    }
    QStringList rememberedFileTabs() const
    {
        return rememberOpenedTabs() ? fileTabs(store.value(QStringLiteral("openedFileTabs")).toStringList()) : QStringList{};
    }
    QVariantList rememberedTabGroups() const
    {
        return rememberOpenedTabs() ? store.value(QStringLiteral("openedTabGroups")).toList() : QVariantList{};
    }
    void setRememberOpenedTabs(bool value)
    {
        if (rememberOpenedTabs() == value) return;
        store.setValue(QStringLiteral("rememberOpenedTabs"), value);
        if (!value) {
            store.remove(QStringLiteral("openedFileTabs"));
            store.remove(QStringLiteral("openedTabGroups"));
        }
        emit changed();
    }
    static QStringList fileTabs(const QStringList &urls)
    {
        QStringList files;
        static const QRegularExpression path(QStringLiteral("^/(file|design|board|proto|slides|deck|site|buzz|make)/[^/?#]+(?:/|$)"));
        for (const auto &address : urls) {
            const QUrl url(address);
            if (url.scheme() == "https" && url.userInfo().isEmpty() && url.port(443) == 443
                && (url.host() == "figma.com" || url.host().endsWith(".figma.com")) && path.match(url.path()).hasMatch())
                files.append(address);
        }
        return files;
    }
    void saveOpenedTabs(QWindow *closing = nullptr)
    {
        if (!rememberOpenedTabs() || safeMode()) return;
        QStringList urls;
        QVariantList groups;
        bool haveWindow = false;
        for (auto *window : registeredWindows) {
            const QVariant tabs = window->property("sessionFileUrls");
            if (!tabs.isValid() || (!window->isVisible() && window != closing)) continue;
            haveWindow = true;
            const auto addresses = tabs.value<QStringList>();
            QMap<int, int> savedIndices;
            for (int index = 0; index < addresses.size(); ++index) {
                if (fileTabs({addresses[index]}).isEmpty()) continue;
                savedIndices.insert(index, urls.size());
                urls.append(addresses[index]);
            }
            const auto groupData = window->property("sessionTabGroups");
            const auto windowGroups = groupData.metaType() == QMetaType::fromType<QJSValue>()
                ? groupData.value<QJSValue>().toVariant().toList() : groupData.toList();
            QSet<int> grouped;
            for (const auto &entry : windowGroups) {
                const auto group = entry.toMap();
                const QColor color(group.value(QStringLiteral("color")).toString());
                const auto title = group.value(QStringLiteral("title")).toString().trimmed();
                if (title.isEmpty() || !color.isValid()) continue;
                QVariantList members;
                for (const auto &member : group.value(QStringLiteral("tabs")).toList()) {
                    bool valid = false;
                    const int index = member.toInt(&valid);
                    if (!valid || !savedIndices.contains(index) || grouped.contains(index)) continue;
                    grouped.insert(index);
                    members.append(savedIndices.value(index));
                }
                if (members.isEmpty()) continue;
                groups.append(QVariantMap{{QStringLiteral("title"), title},
                                          {QStringLiteral("color"), color.name()},
                                          {QStringLiteral("collapsed"), group.value(QStringLiteral("collapsed")).toBool()},
                                          {QStringLiteral("overviewCollapsed"), group.value(QStringLiteral("overviewCollapsed")).toBool()},
                                          {QStringLiteral("tabs"), members}});
            }
        }
        if (!haveWindow) return; // Last-window close already saved its tabs.
        store.setValue(QStringLiteral("openedFileTabs"), urls);
        store.setValue(QStringLiteral("openedTabGroups"), groups);
        store.sync();
    }
    bool figmaSystemColors() const { return store.value(QStringLiteral("figmaSystemColors"), false).toBool(); }
    bool figmaCustomCssEnabled() const { return store.value(QStringLiteral("figmaCustomCssEnabled"), false).toBool(); }
    QString figmaCustomCss() const { return store.value(QStringLiteral("figmaCustomCss")).toString(); }
    bool translucentSidebars() const { return store.value(QStringLiteral("translucentSidebars"), false).toBool(); }
    QString sidebarBackdrop() const { return store.value(QStringLiteral("sidebarBackdrop"), QStringLiteral("desktop")).toString(); }
    QVariantMap figmaPalette() const
    {
        const QPalette palette = QGuiApplication::palette();
        return {
            {QStringLiteral("window"), palette.color(QPalette::Window).name()},
            {QStringLiteral("base"), palette.color(QPalette::Base).name()},
            {QStringLiteral("alternate"), palette.color(QPalette::AlternateBase).name()},
            {QStringLiteral("button"), palette.color(QPalette::Button).name()},
            {QStringLiteral("text"), palette.color(QPalette::WindowText).name()},
            {QStringLiteral("secondaryText"), palette.color(QPalette::PlaceholderText).name()},
            {QStringLiteral("disabledText"), palette.color(QPalette::Disabled, QPalette::WindowText).name()},
            {QStringLiteral("border"), palette.color(QPalette::Mid).name()},
            {QStringLiteral("accent"), palette.color(QPalette::Highlight).name()},
            {QStringLiteral("accentText"), palette.color(QPalette::HighlightedText).name()},
            {QStringLiteral("link"), palette.color(QPalette::Link).name()},
            {QStringLiteral("tooltip"), palette.color(QPalette::ToolTipBase).name()},
            {QStringLiteral("tooltipText"), palette.color(QPalette::ToolTipText).name()}
        };
    }
    bool reduceMotion() const { return store.value(QStringLiteral("reduceMotion"), false).toBool(); }
    int toolbarOpacity() const { return qBound(0, store.value(QStringLiteral("toolbarOpacity"), 100).toInt(), 100); }
    bool windowControlsInTabBar() const { return store.value(QStringLiteral("windowControlsInTabBar"), false).toBool(); }
    bool keepWindowDecorations() const { return store.value(QStringLiteral("keepWindowDecorations"), false).toBool(); }
    bool ignoreToolbarBlur() const { return store.value(QStringLiteral("ignoreToolbarBlur"), false).toBool(); }
    int minimumLoadedTabs() const { return qBound(1, store.value(QStringLiteral("minimumLoadedTabs"), 1).toInt(), 5); }
    int maximumLoadedTabs() const { return qBound(1, store.value(QStringLiteral("maximumLoadedTabs"), 5).toInt(), 100); }
    int sleepMinutes() const { return qBound(1, store.value(QStringLiteral("sleepMinutes"), 5).toInt(), 240); }
    bool sleepingTabPreviews() const { return store.value(QStringLiteral("sleepingTabPreviews"), false).toBool(); }
    bool keepHomeAwake() const { return store.value(QStringLiteral("keepHomeAwake"), true).toBool(); }
    bool releaseClosedWindows() const { return store.value(QStringLiteral("releaseClosedWindows"), true).toBool(); }
    bool cullOffscreenOverviewEffects() const { return store.value(QStringLiteral("cullOffscreenOverviewEffects"), true).toBool(); }
    bool compactPreviewTextures() const { return store.value(QStringLiteral("compactPreviewTextures"), true).toBool(); }
    int overviewPreviewQuality() const { return qBound(25, store.value(QStringLiteral("overviewPreviewQuality"), 100).toInt(), 100); }
    bool gpuRasterization() const { return store.value(QStringLiteral("gpuRasterization"), true).toBool(); }
    bool zeroCopyRasterization() const { return store.value(QStringLiteral("zeroCopyRasterization"), true).toBool(); }
    bool experimentalCanvasFeatures() const { return store.value(QStringLiteral("experimentalCanvasFeatures"), false).toBool(); }
    bool useVulkan() const { return store.value(QStringLiteral("useVulkan"), false).toBool(); }
    QString chromiumFlags() const { return store.value(QStringLiteral("chromiumFlags")).toString(); }
    QString profileStoragePath() const
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
               + QStringLiteral("/ReSketch/QtWebEngine/resketch");
    }
    Q_INVOKABLE void copyToClipboard(const QString &text) const { QGuiApplication::clipboard()->setText(text); }
    bool nativeTabDragSupported() const
    {
        const auto platform = QGuiApplication::platformName();
        return platform != QStringLiteral("offscreen") && platform != QStringLiteral("minimal");
    }
    Q_INVOKABLE QPoint cursorPosition() const { return QCursor::pos(); }
    QVariantList exportHistory() const { return store.value(QStringLiteral("exportHistory")).toList(); }
    Q_INVOKABLE void recordExport(const QString &directory, const QString &fileName,
                                 const QString &originName, const QUrl &originUrl)
    {
        const QFileInfo file(QDir(directory).filePath(fileName));
        if (!file.isFile())
            return;
        auto history = exportHistory();
        const QString path = file.absoluteFilePath();
        history.removeIf([&path](const QVariant &entry) { return entry.toMap().value(QStringLiteral("path")).toString() == path; });
        history.prepend(QVariantMap{
            {QStringLiteral("path"), path}, {QStringLiteral("name"), file.fileName()},
            {QStringLiteral("url"), QUrl::fromLocalFile(path)},
            {QStringLiteral("fileType"), file.suffix().toUpper()},
            {QStringLiteral("originName"), originName}, {QStringLiteral("originUrl"), originUrl},
            {QStringLiteral("exportedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}
        });
        store.setValue(QStringLiteral("exportHistory"), history);
        emit exportHistoryChanged();
    }
    Q_INVOKABLE bool openExport(const QString &path, bool folder) const
    {
        return QDesktopServices::openUrl(QUrl::fromLocalFile(folder ? QFileInfo(path).absolutePath() : path));
    }
    Q_INVOKABLE bool deleteExport(const QString &path)
    {
        auto history = exportHistory();
        const auto matches = [&path](const QVariant &entry) { return entry.toMap().value(QStringLiteral("path")).toString() == path; };
        if (std::none_of(history.cbegin(), history.cend(), matches))
            return false;
        if (QFileInfo::exists(path) && !QFile::remove(path))
            return false;
        history.removeIf(matches);
        store.setValue(QStringLiteral("exportHistory"), history);
        emit exportHistoryChanged();
        return true;
    }
    Q_INVOKABLE void clearExports()
    {
        store.remove(QStringLiteral("exportHistory"));
        emit exportHistoryChanged();
    }
    Q_INVOKABLE void resetSettings()
    {
        // Export records and per-document folders are user data, not preferences.
        for (const QString &key : store.allKeys()) {
            if (key != QStringLiteral("exportHistory") && !key.startsWith(QStringLiteral("exportFolders/")))
                store.remove(key);
        }
        // Keep a reset from importing legacy preferences on next launch.
        store.setValue(QStringLiteral("settingsInitialized"), true);
        store.sync();
        applyTheme();
        emit changed();
        emit effectiveThemeChanged();
        emit figmaAppearanceChanged();
    }
    Q_INVOKABLE QString chooseExportFolder(const QString &fileKey, const QString &fileName, QObject *owner)
    {
        const bool remember = QRegularExpression(QStringLiteral("^[a-zA-Z0-9_-]+$")).match(fileKey).hasMatch();
        const QString setting = QStringLiteral("exportFolders/") + fileKey;
        QString initial = remember ? store.value(setting).toString() : QString();
        if (!QFileInfo(initial).isDir())
            initial = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
        if (!QFileInfo(initial).isDir())
            initial = QDir::homePath();

        QFileDialog dialog;
        dialog.setWindowTitle(fileName.isEmpty() ? tr("Choose export folder")
                                                : tr("Choose export folder — %1").arg(fileName));
        dialog.setFileMode(QFileDialog::Directory);
        dialog.setOption(QFileDialog::ShowDirsOnly);
        dialog.setSupportedSchemes({QStringLiteral("file")});
        dialog.setLabelText(QFileDialog::Accept, tr("Export here"));
        dialog.setDirectory(initial);
        auto *window = qobject_cast<QWindow *>(owner);
        dialog.setWindowModality(window ? Qt::WindowModal : Qt::ApplicationModal);
        dialog.winId();
        if (window)
            dialog.windowHandle()->setTransientParent(window);
        // Qt Quick rejects requests after downloadRequested returns without accept().
        // Keep the native picker synchronous so no download starts before choosing.
        if (dialog.exec() != QDialog::Accepted || dialog.selectedFiles().isEmpty())
            return {};
        const QString folder = dialog.selectedFiles().first();
        if (remember)
            store.setValue(setting, folder);
        return folder;
    }
    Q_INVOKABLE void repaintWebView(QObject *object) const
    {
        const QPointer<QQuickItem> view = qobject_cast<QQuickItem *>(object);
        if (!view || !view->isVisible())
            return;
        const auto repaint = [view] {
            if (!view || !view->isVisible()) return;
            // WebEngine paints through a child item, including inside overview layers.
            const auto update = [](const auto &self, QQuickItem *item) -> void {
                if (item->flags().testFlag(QQuickItem::ItemHasContents)) item->update();
                for (auto *child : item->childItems()) self(self, child);
            };
            update(update, view);
            if (auto *window = view->window()) window->update();
        };
        repaint();
        // Figma's theme dispatch and sidebar masks paint after the JS callback.
        // Refresh those later frames too, without waking hidden or destroyed views.
        QTimer::singleShot(50, this, repaint);
        QTimer::singleShot(150, this, repaint);
    }

    Q_INVOKABLE void refreshWindowBlur(QObject *object) const
    {
        auto *window = qobject_cast<QWindow *>(object);
        if (!window)
            return;
        const bool desktopSidebars = translucentSidebars() && sidebarBackdrop() == QStringLiteral("desktop");
        const int blurHeight = window->property("chromiumFrameLoaded").toBool() && !desktopSidebars
                                   ? window->property("tabStripHeight").toInt() : window->height();
        const QRegion region(0, 0, window->width(), blurHeight);
        KWindowEffects::enableBlurBehind(window, !safeMode() && toolbarOpacity() < 100 && !ignoreToolbarBlur(), region);
    }
    Q_INVOKABLE void registerMainWindow(QObject *object)
    {
        auto *window = qobject_cast<QWindow *>(object);
        if (!window || registeredWindows.contains(window))
            return;
        registeredWindows.insert(window);
        const auto updateBlur = [this, window] { refreshWindowBlur(window); };
        connect(window, &QWindow::widthChanged, window, updateBlur);
        connect(window, &QWindow::heightChanged, window, updateBlur);
        connect(window, &QWindow::visibilityChanged, window, updateBlur);
        connect(this, &AppSettings::changed, window, [window, updateBlur] {
            QTimer::singleShot(0, window, updateBlur);
        });
        connect(window, &QObject::destroyed, this, [this, window] { registeredWindows.remove(window); });
        if (auto *quickWindow = qobject_cast<QQuickWindow *>(window)) {
            // Query the active device on its render thread, after initialization.
            connect(quickWindow, &QQuickWindow::beforeRendering, this,
                    [this, quickWindow, checked = false]() mutable {
                if (checked) return;
                checked = true;
                const bool accelerated = hasGraphicsAcceleration(quickWindow);
                const QStringList flags = qEnvironmentVariable("QTWEBENGINE_CHROMIUM_FLAGS").split(' ', Qt::SkipEmptyParts);
                const bool webGpuDisabled = flags.contains(QStringLiteral("--disable-gpu"))
                    || flags.contains(QStringLiteral("--use-angle=swiftshader"))
                    || flags.contains(QStringLiteral("--use-gl=swiftshader"));
                QMetaObject::invokeMethod(this, [this, accelerated, webGpuDisabled] {
                    if (graphicsChecked) return;
                    graphicsChecked = true;
                    if (!accelerated || webGpuDisabled) {
                        graphicsWarning = tr("GPU acceleration could not be detected. ReSketch may render more slowly with software rendering.");
                        emit gpuAccelerationWarningChanged();
                    }
                }, Qt::QueuedConnection);
            }, Qt::DirectConnection);
        }
        QTimer::singleShot(0, window, updateBlur);
    }

    void setTheme(const QString &value)
    {
        if ((value != QStringLiteral("auto") && value != QStringLiteral("light")
             && value != QStringLiteral("dark")) || theme() == value)
            return;
        store.setValue(QStringLiteral("theme"), value);
        applyTheme();
        emit effectiveThemeChanged();
        emit changed();
    }
    void setMenuIntegration(bool value)
    {
        if (menuIntegration() == value)
            return;
        store.setValue(QStringLiteral("menuIntegration"), value);
        emit changed();
    }
    void setFigmaSystemColors(bool value)
    {
        if (figmaSystemColors() == value)
            return;
        store.setValue(QStringLiteral("figmaSystemColors"), value);
        emit changed();
        emit figmaAppearanceChanged();
    }
    void setFigmaCustomCssEnabled(bool value)
    {
        if (figmaCustomCssEnabled() == value)
            return;
        store.setValue(QStringLiteral("figmaCustomCssEnabled"), value);
        emit changed();
        emit figmaAppearanceChanged();
    }
    void setFigmaCustomCss(const QString &value)
    {
        if (figmaCustomCss() == value)
            return;
        store.setValue(QStringLiteral("figmaCustomCss"), value);
        emit changed();
        emit figmaAppearanceChanged();
    }
    void setTranslucentSidebars(bool value)
    {
        if (translucentSidebars() == value)
            return;
        store.setValue(QStringLiteral("translucentSidebars"), value);
        emit changed();
        emit figmaAppearanceChanged();
    }
    void setSidebarBackdrop(const QString &value)
    {
        if ((value != QStringLiteral("desktop") && value != QStringLiteral("canvas")) || sidebarBackdrop() == value)
            return;
        store.setValue(QStringLiteral("sidebarBackdrop"), value);
        emit changed();
        emit figmaAppearanceChanged();
    }
    void setReduceMotion(bool value)
    {
        if (reduceMotion() == value)
            return;
        store.setValue(QStringLiteral("reduceMotion"), value);
        emit changed();
    }
    void setToolbarOpacity(int value)
    {
        value = qBound(0, value, 100);
        if (toolbarOpacity() == value)
            return;
        store.setValue(QStringLiteral("toolbarOpacity"), value);
        emit changed();
        if (translucentSidebars())
            emit figmaAppearanceChanged();
    }
    void setWindowControlsInTabBar(bool value)
    {
        if (windowControlsInTabBar() == value)
            return;
        store.setValue(QStringLiteral("windowControlsInTabBar"), value);
        emit changed();
    }
    void setKeepWindowDecorations(bool value)
    {
        if (keepWindowDecorations() == value)
            return;
        store.setValue(QStringLiteral("keepWindowDecorations"), value);
        emit changed();
    }
    void setIgnoreToolbarBlur(bool value)
    {
        if (ignoreToolbarBlur() == value)
            return;
        store.setValue(QStringLiteral("ignoreToolbarBlur"), value);
        emit changed();
    }
    void setMinimumLoadedTabs(int value)
    {
        value = qBound(1, value, 5);
        if (minimumLoadedTabs() == value)
            return;
        store.setValue(QStringLiteral("minimumLoadedTabs"), value);
        emit changed();
    }
    void setMaximumLoadedTabs(int value)
    {
        value = qBound(1, value, 100);
        if (maximumLoadedTabs() == value)
            return;
        store.setValue(QStringLiteral("maximumLoadedTabs"), value);
        emit changed();
    }
    void setSleepMinutes(int value)
    {
        value = qBound(1, value, 240);
        if (sleepMinutes() == value)
            return;
        store.setValue(QStringLiteral("sleepMinutes"), value);
        emit changed();
    }
    void setSleepingTabPreviews(bool value)
    {
        if (sleepingTabPreviews() == value)
            return;
        store.setValue(QStringLiteral("sleepingTabPreviews"), value);
        emit changed();
    }
    void setKeepHomeAwake(bool value)
    {
        if (keepHomeAwake() == value)
            return;
        store.setValue(QStringLiteral("keepHomeAwake"), value);
        emit changed();
    }
    void setReleaseClosedWindows(bool value)
    {
        if (releaseClosedWindows() == value)
            return;
        store.setValue(QStringLiteral("releaseClosedWindows"), value);
        emit changed();
    }
    void setCullOffscreenOverviewEffects(bool value)
    {
        if (cullOffscreenOverviewEffects() == value)
            return;
        store.setValue(QStringLiteral("cullOffscreenOverviewEffects"), value);
        emit changed();
    }
    void setCompactPreviewTextures(bool value)
    {
        if (compactPreviewTextures() == value)
            return;
        store.setValue(QStringLiteral("compactPreviewTextures"), value);
        emit changed();
    }
    void setOverviewPreviewQuality(int value)
    {
        value = qBound(25, value, 100);
        if (overviewPreviewQuality() == value)
            return;
        store.setValue(QStringLiteral("overviewPreviewQuality"), value);
        emit changed();
    }
    void setGpuRasterization(bool value)
    {
        if (gpuRasterization() == value)
            return;
        store.setValue(QStringLiteral("gpuRasterization"), value);
        emit changed();
    }
    void setZeroCopyRasterization(bool value)
    {
        if (zeroCopyRasterization() == value)
            return;
        store.setValue(QStringLiteral("zeroCopyRasterization"), value);
        emit changed();
    }
    void setExperimentalCanvasFeatures(bool value)
    {
        if (experimentalCanvasFeatures() == value)
            return;
        store.setValue(QStringLiteral("experimentalCanvasFeatures"), value);
        emit changed();
    }
    void setUseVulkan(bool value)
    {
        if (useVulkan() == value)
            return;
        store.setValue(QStringLiteral("useVulkan"), value);
        emit changed();
    }
    void setChromiumFlags(const QString &value)
    {
        if (chromiumFlags() == value)
            return;
        store.setValue(QStringLiteral("chromiumFlags"), value);
        emit changed();
    }

signals:
    void gpuAccelerationWarningChanged();
    void exportHistoryChanged();
    void changed();
    void effectiveThemeChanged();
    void figmaAppearanceChanged();

private:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Close) {
            auto *window = qobject_cast<QWindow *>(watched);
            if (registeredWindows.contains(window)) saveOpenedTabs(window);
        }
        if (watched == qGuiApp && event->type() == QEvent::ApplicationPaletteChange)
            emit effectiveThemeChanged();
        return QObject::eventFilter(watched, event);
    }

    void applyTheme()
    {
        const Qt::ColorScheme scheme = safeMode() ? Qt::ColorScheme::Unknown
                                       : theme() == QStringLiteral("dark") ? Qt::ColorScheme::Dark
                                       : theme() == QStringLiteral("light") ? Qt::ColorScheme::Light
                                                                            : Qt::ColorScheme::Unknown;
        QGuiApplication::styleHints()->setColorScheme(scheme);
    }

    QSettings store;
    const bool recoveryMode;
    QSet<QWindow *> registeredWindows;
    bool graphicsChecked = false;
    QString graphicsWarning;
};

int main(int argc, char *argv[])
{
    QStringList arguments;
    for (int index = 1; index < argc; ++index)
        arguments.append(QString::fromLocal8Bit(argv[index]));
    bool safeMode = arguments.contains(QStringLiteral("--safe-mode")) || heldAltKey().value_or(false);
    if (safeMode) {
        qputenv("QT_QUICK_BACKEND", "software");
        QCoreApplication::setAttribute(Qt::AA_UseSoftwareOpenGL);
    }
    // This attribute provides the same context sharing as initialize(), without
    // starting Chromium before the launch-time modifier check.
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QQuickWindow::setDefaultAlphaBuffer(true);
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("ReSketch"));
    QApplication::setOrganizationName(QStringLiteral("aether64"));
    QApplication::setDesktopFileName(QStringLiteral("org.aether64.resketch"));
    QApplication::setWindowIcon(QIcon(QStringLiteral(":/Branding/SketchbookPNG/Folder-256.png")));
    safeMode = safeMode || requestedSafeMode(app.arguments());
    if (safeMode) {
        // Ignore both saved and environment Chromium switches during recovery.
        fprintf(stderr, "ReSketch: safe mode (software rendering, settings only)\n");
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", "--disable-gpu --disable-gpu-compositing --disable-gpu-rasterization --disable-zero-copy --disable-features=Vulkan --use-vulkan=none");
        qputenv("QT_QUICK_BACKEND", "software");
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    }
    QSettings startupSettings(QStringLiteral("aether64"), QStringLiteral("ReSketch"));
    if (startupSettings.allKeys().isEmpty()) {
        QSettings previousSettings(QStringLiteral("ReSketch"), QStringLiteral("ReSketch"));
        for (const QString &key : previousSettings.allKeys())
            startupSettings.setValue(key, previousSettings.value(key));
    }
    if (!safeMode) {
        QByteArray chromiumFlags = startupSettings.value(QStringLiteral("gpuRasterization"), true).toBool()
                                       ? QByteArrayLiteral("--enable-gpu-rasterization")
                                       : QByteArrayLiteral("--disable-gpu-rasterization");
        chromiumFlags += startupSettings.value(QStringLiteral("zeroCopyRasterization"), true).toBool()
                             ? QByteArrayLiteral(" --enable-zero-copy")
                             : QByteArrayLiteral(" --disable-zero-copy");
        if (startupSettings.value(QStringLiteral("experimentalCanvasFeatures"), false).toBool())
            chromiumFlags += QByteArrayLiteral(" --enable-experimental-canvas-features");
        if (startupSettings.value(QStringLiteral("useVulkan"), false).toBool())
            chromiumFlags += QByteArrayLiteral(" --use-gl=angle --enable-features=Vulkan --use-vulkan=native");
        // External and custom switches stay last so they can override these toggles.
        const QByteArray environmentFlags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS").trimmed();
        if (!environmentFlags.isEmpty())
            chromiumFlags += ' ' + environmentFlags;
        const QByteArray userFlags = startupSettings.value(QStringLiteral("chromiumFlags")).toString().toUtf8().trimmed();
        if (!userFlags.isEmpty())
            chromiumFlags += ' ' + userFlags;
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", chromiumFlags);
    }
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    QString incomingUrl;
    for (const QString &argument : app.arguments().mid(1)) {
        if (!argument.startsWith('-')) {
            incomingUrl = argument;
            break;
        }
    }
    const QString socketPath = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
                               + (safeMode ? QStringLiteral("/resketch-safe-mode.sock") : QStringLiteral("/resketch.sock"));
    QLocalSocket existing;
    existing.connectToServer(socketPath);
    if (existing.waitForConnected(250)) {
        existing.write((incomingUrl.isEmpty() ? QByteArrayLiteral("resketch:home") : incomingUrl.toUtf8()) + '\n');
        existing.waitForBytesWritten(1000);
        return 0;
    }

    QLocalServer::removeServer(socketPath);
    QLocalServer server;
    server.setSocketOptions(QLocalServer::UserAccessOption);
    if (!server.listen(socketPath))
        fprintf(stderr, "ReSketch: cannot listen for Figma links: %s\n", qPrintable(server.errorString()));

    AppSettings appSettings(&app, safeMode);
    std::unique_ptr<FontHelper> fontHelper;
    if (!safeMode) fontHelper = std::make_unique<FontHelper>();
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"), &appSettings);
    // Recovery deliberately loads only Settings: no WebEngine profile, page,
    // custom CSS, overview effects, animations, or native menu integration.
    engine.loadFromModule("org.aether64.resketch", safeMode ? "SettingsWindow" : "Main");
    if (engine.rootObjects().isEmpty()) {
        fprintf(stderr, "ReSketch: QML window could not be loaded\n");
        return 1;
    }

    QObject *window = engine.rootObjects().first();
    if (safeMode) {
        auto *recoveryWindow = qobject_cast<QWindow *>(window);
        recoveryWindow->show();
        recoveryWindow->requestActivate();
    }
    const auto deliverUrl = [window, safeMode](const QString &url) {
        if (!safeMode) {
            window->setProperty("externalUrl", QString());
            window->setProperty("externalUrl", url);
        }
        if (auto *appWindow = qobject_cast<QWindow *>(window)) {
            appWindow->raise();
            appWindow->requestActivate();
        }
    };
    QObject::connect(&server, &QLocalServer::newConnection, &app, [&server, deliverUrl] {
        while (QLocalSocket *socket = server.nextPendingConnection()) {
            QObject::connect(socket, &QLocalSocket::readyRead, socket, [socket, deliverUrl] {
                if (socket->bytesAvailable() > 4096) {
                    socket->disconnectFromServer();
                    return;
                }
                if (!socket->canReadLine())
                    return;
                const QByteArray input = socket->readLine(4097);
                if (input.size() <= 4096 && input.endsWith('\n'))
                    deliverUrl(QString::fromUtf8(input.chopped(1)));
                socket->disconnectFromServer();
            });
            QObject::connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
        }
    });
    if (!incomingUrl.isEmpty())
        deliverUrl(incomingUrl);
    return app.exec();
}

#include "main.moc"
