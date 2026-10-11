#include <QApplication>
#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPalette>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QStyleHints>
#include <QTimer>
#include <QWindow>
#include <KWindowEffects>
#include <cstdio>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <unistd.h>

class AppSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY changed)
    Q_PROPERTY(bool darkTheme READ darkTheme NOTIFY effectiveThemeChanged)
    Q_PROPERTY(bool menuIntegration READ menuIntegration WRITE setMenuIntegration NOTIFY changed)
    Q_PROPERTY(bool reduceMotion READ reduceMotion WRITE setReduceMotion NOTIFY changed)
    Q_PROPERTY(int toolbarOpacity READ toolbarOpacity WRITE setToolbarOpacity NOTIFY changed)
    Q_PROPERTY(bool windowControlsInTabBar READ windowControlsInTabBar WRITE setWindowControlsInTabBar NOTIFY changed)
    Q_PROPERTY(bool keepWindowDecorations READ keepWindowDecorations WRITE setKeepWindowDecorations NOTIFY changed)
    Q_PROPERTY(bool ignoreToolbarBlur READ ignoreToolbarBlur WRITE setIgnoreToolbarBlur NOTIFY changed)
    Q_PROPERTY(int minimumLoadedTabs READ minimumLoadedTabs WRITE setMinimumLoadedTabs NOTIFY changed)
    Q_PROPERTY(int sleepMinutes READ sleepMinutes WRITE setSleepMinutes NOTIFY changed)
    Q_PROPERTY(int maxMemoryGb READ maxMemoryGb WRITE setMaxMemoryGb NOTIFY changed)
    Q_PROPERTY(bool highRefreshRate READ highRefreshRate WRITE setHighRefreshRate NOTIFY changed)
    Q_PROPERTY(bool gpuRasterization READ gpuRasterization WRITE setGpuRasterization NOTIFY changed)
    Q_PROPERTY(bool zeroCopyRasterization READ zeroCopyRasterization WRITE setZeroCopyRasterization NOTIFY changed)
    Q_PROPERTY(QString chromiumFlags READ chromiumFlags WRITE setChromiumFlags NOTIFY changed)
    Q_PROPERTY(QString profileStoragePath READ profileStoragePath CONSTANT)

public:
    explicit AppSettings(QObject *parent = nullptr)
        : QObject(parent), store(QStringLiteral("aether64"), QStringLiteral("ReSketch"))
    {
        applyTheme();
        connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, this,
                [this] { emit effectiveThemeChanged(); });
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
    bool reduceMotion() const { return store.value(QStringLiteral("reduceMotion"), false).toBool(); }
    int toolbarOpacity() const { return qBound(0, store.value(QStringLiteral("toolbarOpacity"), 100).toInt(), 100); }
    bool windowControlsInTabBar() const { return store.value(QStringLiteral("windowControlsInTabBar"), false).toBool(); }
    bool keepWindowDecorations() const { return store.value(QStringLiteral("keepWindowDecorations"), false).toBool(); }
    bool ignoreToolbarBlur() const { return store.value(QStringLiteral("ignoreToolbarBlur"), false).toBool(); }
    int minimumLoadedTabs() const { return qBound(1, store.value(QStringLiteral("minimumLoadedTabs"), 1).toInt(), 5); }
    int sleepMinutes() const { return qBound(1, store.value(QStringLiteral("sleepMinutes"), 5).toInt(), 240); }
    int maxMemoryGb() const { return qBound(1, store.value(QStringLiteral("maxMemoryGb"), 5).toInt(), 64); }
    bool highRefreshRate() const { return store.value(QStringLiteral("highRefreshRate"), true).toBool(); }
    bool gpuRasterization() const { return store.value(QStringLiteral("gpuRasterization"), true).toBool(); }
    bool zeroCopyRasterization() const { return store.value(QStringLiteral("zeroCopyRasterization"), true).toBool(); }
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
    Q_INVOKABLE void refreshWindowBlur(QObject *object) const
    {
        auto *window = qobject_cast<QWindow *>(object);
        if (!window)
            return;
        const int blurHeight = window->property("chromiumFrameLoaded").toBool()
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
    void setSleepMinutes(int value)
    {
        value = qBound(1, value, 240);
        if (sleepMinutes() == value)
            return;
        store.setValue(QStringLiteral("sleepMinutes"), value);
        emit changed();
    }
    void setMaxMemoryGb(int value)
    {
        value = qBound(1, value, 64);
        if (maxMemoryGb() == value)
            return;
        store.setValue(QStringLiteral("maxMemoryGb"), value);
        emit changed();
    }
    void setHighRefreshRate(bool value)
    {
        if (highRefreshRate() == value)
            return;
        store.setValue(QStringLiteral("highRefreshRate"), value);
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
    void setChromiumFlags(const QString &value)
    {
        if (chromiumFlags() == value)
            return;
        store.setValue(QStringLiteral("chromiumFlags"), value);
        emit changed();
    }

signals:
    void changed();
    void effectiveThemeChanged();

private:
    void applyTheme()
    {
        const Qt::ColorScheme scheme = theme() == QStringLiteral("dark") ? Qt::ColorScheme::Dark
                                       : theme() == QStringLiteral("light") ? Qt::ColorScheme::Light
                                                                            : Qt::ColorScheme::Unknown;
        QGuiApplication::styleHints()->setColorScheme(scheme);
    }

    QSettings store;
    QSet<QWindow *> registeredWindows;
};

static qint64 processMemory(qint64 pid)
{
    QFile smaps(QStringLiteral("/proc/%1/smaps_rollup").arg(pid));
    if (smaps.open(QIODevice::ReadOnly)) {
        while (!smaps.atEnd()) {
            const QByteArray line = smaps.readLine();
            if (line.startsWith("Pss:"))
                return line.mid(4).trimmed().split(' ').first().toLongLong() * 1024;
        }
    }

    QFile statm(QStringLiteral("/proc/%1/statm").arg(pid));
    if (statm.open(QIODevice::ReadOnly)) {
        const QList<QByteArray> fields = statm.readAll().simplified().split(' ');
        if (fields.size() > 1)
            return fields[1].toLongLong() * sysconf(_SC_PAGESIZE);
    }
    return 0;
}

static qint64 appMemory()
{
    QHash<qint64, QList<qint64>> childrenByParent;
    const QDir proc(QStringLiteral("/proc"));
    for (const QString &entry : proc.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool valid = false;
        const qint64 pid = entry.toLongLong(&valid);
        if (!valid)
            continue;
        QFile status(proc.filePath(entry + QStringLiteral("/status")));
        if (!status.open(QIODevice::ReadOnly))
            continue;
        while (!status.atEnd()) {
            const QByteArray line = status.readLine();
            if (line.startsWith("PPid:")) {
                const qint64 parent = line.mid(5).trimmed().toLongLong();
                childrenByParent[parent].append(pid);
                break;
            }
        }
    }

    QList<qint64> pending{QCoreApplication::applicationPid()};
    QSet<qint64> seen;
    qint64 bytes = 0;
    while (!pending.isEmpty()) {
        const qint64 pid = pending.takeLast();
        if (seen.contains(pid))
            continue;
        seen.insert(pid);
        bytes += processMemory(pid);
        pending.append(childrenByParent.value(pid));
    }
    return bytes;
}

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
    // Keep Qt Quick's animations in step with the display, including mixed-rate
    // monitor setups. Vsync stays enabled; none of these uncaps Chromium.
    if (startupSettings.value(QStringLiteral("highRefreshRate"), true).toBool()) {
        if (!qEnvironmentVariableIsSet("QSG_RENDER_LOOP"))
            qputenv("QSG_RENDER_LOOP", QByteArrayLiteral("threaded"));
        if (!qEnvironmentVariableIsSet("QSG_USE_SIMPLE_ANIMATION_DRIVER"))
            qputenv("QSG_USE_SIMPLE_ANIMATION_DRIVER", QByteArrayLiteral("1"));
        if (!qEnvironmentVariableIsSet("QT_QPA_UPDATE_IDLE_TIME"))
            qputenv("QT_QPA_UPDATE_IDLE_TIME", QByteArrayLiteral("0"));
    }

    QByteArray chromiumFlags = startupSettings.value(QStringLiteral("gpuRasterization"), true).toBool()
                                   ? QByteArrayLiteral("--enable-gpu-rasterization")
                                   : QByteArrayLiteral("--disable-gpu-rasterization");
    chromiumFlags += startupSettings.value(QStringLiteral("zeroCopyRasterization"), true).toBool()
                         ? QByteArrayLiteral(" --enable-zero-copy")
                         : QByteArrayLiteral(" --disable-zero-copy");
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
    QTimer memoryTimer;
    memoryTimer.setInterval(10000);
    const auto updateMemory = [] {
        const qint64 bytes = appMemory();
        for (QWindow *candidate : QGuiApplication::allWindows()) {
            if (candidate->property("tabStripHeight").isValid())
                candidate->setProperty("appMemoryBytes", bytes);
        }
    };
    QObject::connect(&memoryTimer, &QTimer::timeout, &app, updateMemory);
    memoryTimer.start();
    updateMemory();
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
