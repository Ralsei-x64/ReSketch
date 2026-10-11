#include <QApplication>
#include <QClipboard>
#include <QCursor>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPalette>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
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
#include <KWindowEffects>
#include <algorithm>
#include <cstdio>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#if QT_CONFIG(vulkan)
#include <QVulkanFunctions>
#include <QVulkanInstance>
#endif

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

public:
    QString gpuAccelerationWarning() const { return graphicsWarning; }
    explicit AppSettings(QObject *parent = nullptr)
        : QObject(parent), store(QStringLiteral("aether64"), QStringLiteral("ReSketch"))
    {
        applyTheme();
        connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, this,
                [this] { emit effectiveThemeChanged(); });
        qGuiApp->installEventFilter(this);
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
        // Keep existing sign-in sessions across both app ID changes.
        const QString data = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
        for (const QString &legacy : {
                 data + QStringLiteral("/KFigma/KFigma/QtWebEngine/kfigma"),
                 data + QStringLiteral("/ReSketch/ReSketch/QtWebEngine/resketch")}) {
            if (QDir(legacy).exists())
                return legacy;
        }
        return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
               + QStringLiteral("/QtWebEngine/resketch");
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
    Q_INVOKABLE void refreshWindowBlur(QObject *object) const
    {
        auto *window = qobject_cast<QWindow *>(object);
        if (!window)
            return;
        const bool desktopSidebars = translucentSidebars() && sidebarBackdrop() == QStringLiteral("desktop");
        const int blurHeight = window->property("chromiumFrameLoaded").toBool() && !desktopSidebars
                                   ? window->property("tabStripHeight").toInt() : window->height();
        const QRegion region(0, 0, window->width(), blurHeight);
        KWindowEffects::enableBlurBehind(window, toolbarOpacity() < 100 && !ignoreToolbarBlur(), region);
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
        if (watched == qGuiApp && event->type() == QEvent::ApplicationPaletteChange)
            emit effectiveThemeChanged();
        return QObject::eventFilter(watched, event);
    }

    void applyTheme()
    {
        const Qt::ColorScheme scheme = theme() == QStringLiteral("dark") ? Qt::ColorScheme::Dark
                                       : theme() == QStringLiteral("light") ? Qt::ColorScheme::Light
                                                                            : Qt::ColorScheme::Unknown;
        QGuiApplication::styleHints()->setColorScheme(scheme);
    }

    QSettings store;
    QSet<QWindow *> registeredWindows;
    bool graphicsChecked = false;
    QString graphicsWarning;
};

int main(int argc, char *argv[])
{
    QSettings startupSettings(QStringLiteral("aether64"), QStringLiteral("ReSketch"));
    if (startupSettings.allKeys().isEmpty()) {
        for (const QString &name : {QStringLiteral("ReSketch"), QStringLiteral("KFigma")}) {
            QSettings previousSettings(name, name);
            if (previousSettings.allKeys().isEmpty())
                continue;
            for (const QString &key : previousSettings.allKeys())
                startupSettings.setValue(key, previousSettings.value(key));
            break;
        }
    }
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
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QQuickWindow::setDefaultAlphaBuffer(true);
    QtWebEngineQuick::initialize();

    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("ReSketch"));
    QApplication::setOrganizationName(QStringLiteral("aether64"));
    QApplication::setDesktopFileName(QStringLiteral("org.aether64.resketch"));
    QApplication::setWindowIcon(QIcon(QStringLiteral(":/Branding/SketchbookPNG/Folder-256.png")));
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    const QString incomingUrl = app.arguments().value(1);
    const QString socketPath = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
                               + QStringLiteral("/resketch.sock");
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

    AppSettings appSettings(&app);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"), &appSettings);
    engine.loadFromModule("org.aether64.resketch", "Main");
    if (engine.rootObjects().isEmpty()) {
        fprintf(stderr, "ReSketch: QML window could not be loaded\n");
        return 1;
    }

    QObject *window = engine.rootObjects().first();
    const auto deliverUrl = [window](const QString &url) {
        window->setProperty("externalUrl", QString());
        window->setProperty("externalUrl", url);
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
