// Exercise the real settings window with Qt Widgets and Kirigami together.
#define main resketchMain
#include "../src/main.cpp"
#undef main
#include <QQmlComponent>
#include <QQmlExpression>
#include <QQuickItem>
#include <QTemporaryDir>
#include <KIconLoader>
#include <cassert>

int main(int argc, char **argv)
{
    qputenv("XDG_CURRENT_DESKTOP", "GNOME");
    KIconTheme::initTheme();
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("resketch-theme-test"));
    QTemporaryDir temporary;
    assert(temporary.isValid());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, temporary.path());
    // Reproduce a dark widget style on a desktop with no KDE color settings.
    QPalette nativePalette = QApplication::palette();
    nativePalette.setColor(QPalette::Window, QColor("#353535"));
    nativePalette.setColor(QPalette::WindowText, QColor("#eeeeec"));
    QApplication::setPalette(nativePalette);
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    AppSettings settings;
    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"), &settings);
    QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(RESKETCH_SOURCE_DIR "/src/SettingsWindow.qml")));
    QScopedPointer<QObject> object(component.create());
    if (!object) {
        fprintf(stderr, "%s\n", qPrintable(component.errorString()));
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(object.data());
    assert(window);
    window->show();
    const auto color = [&](const QString &expression) {
        QQmlExpression binding(qmlContext(window), window, expression);
        const QVariant result = binding.evaluate();
        assert(!binding.hasError());
        const QColor value = result.value<QColor>();
        assert(value.isValid());
        return value;
    };
    const bool systemDark = settings.darkTheme();
    for (const QString &theme : {QStringLiteral("auto"), QStringLiteral("light"),
                                QStringLiteral("dark"), QStringLiteral("auto")}) {
        settings.setTheme(theme);
        QTimer::singleShot(150, &app, &QCoreApplication::quit);
        app.exec();
        const bool expectedDark = theme == QStringLiteral("auto") ? systemDark : theme == QStringLiteral("dark");
        const QColor background = color(QStringLiteral("Kirigami.Theme.backgroundColor"));
        const QColor text = color(QStringLiteral("Kirigami.Theme.textColor"));
        const QColor widgetBackground = color(QStringLiteral("palette.window"));
        const QColor widgetText = color(QStringLiteral("palette.windowText"));
        fprintf(stderr, "%s: Kirigami %s/%s, Qt %s/%s\n", qPrintable(theme),
                qPrintable(background.name()), qPrintable(text.name()),
                qPrintable(widgetBackground.name()), qPrintable(widgetText.name()));
        assert(settings.darkTheme() == expectedDark);
        assert((background.lightness() < 128) == expectedDark);
        assert((widgetBackground.lightness() < 128) == expectedDark);
        assert(qAbs(background.lightness() - text.lightness()) > 96);
        assert(qAbs(widgetBackground.lightness() - widgetText.lightness()) > 96);
        for (const QString &name : {QStringLiteral("go-home"), QStringLiteral("go-previous"),
                                   QStringLiteral("tab-new"), QStringLiteral("view-grid"),
                                   QStringLiteral("application-menu"), QStringLiteral("window-close"),
                                   QStringLiteral("preferences-desktop-theme"),
                                   QStringLiteral("preferences-system-performance"), QStringLiteral("tab-duplicate")}) {
            assert(!KIconLoader::global()->iconPath(name, KIconLoader::Small, true).isEmpty());
            assert(!QIcon::fromTheme(name).pixmap(24).isNull());
        }
        const QImage screenshot = window->grabWindow();
        assert(!screenshot.isNull());
        bool checkedComboBox = false;
        for (auto *item : window->findChildren<QQuickItem *>()) {
            if (!item->inherits("QQuickComboBox") || item->width() <= 0 || !item->isVisible())
                continue;
            // Check a blank part of the rendered control, since some widget
            // styles ignore the palette when drawing their backgrounds.
            const QPointF point = item->mapToScene(QPointF(item->width() * 0.7, item->height() * 0.7));
            const QColor surface = screenshot.pixelColor(qRound(point.x() * screenshot.width() / window->width()),
                                                        qRound(point.y() * screenshot.height() / window->height()));
            assert((surface.lightness() < 128) == expectedDark);
            checkedComboBox = true;
            break;
        }
        assert(checkedComboBox);
        if (argc > 1) {
            QDir().mkpath(QString::fromUtf8(argv[1]));
            assert(screenshot.save(QString::fromUtf8(argv[1]) + '/' + theme + QStringLiteral(".png")));
        }
    }
    fprintf(stderr, "Qt and Kirigami theme switching checks passed\n");
}
