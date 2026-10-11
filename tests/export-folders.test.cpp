// Build after the app to reuse its generated moc; see tests/check-export-folders.sh.
#define main resketchMain
#include "../src/main.cpp"
#undef main
#include <QTemporaryDir>
#include <cassert>

int main(int argc, char **argv)
{
    QApplication::setAttribute(Qt::AA_DontUseNativeDialogs);
    QApplication app(argc, argv);
    QTemporaryDir temporary;
    assert(temporary.isValid());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, temporary.path());
    const QString first = temporary.path() + "/first";
    const QString second = temporary.path() + "/second";
    QDir().mkpath(first);
    QDir().mkpath(second);
    QString fallback = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (!QFileInfo(fallback).isDir()) fallback = QDir::homePath();
    const auto choose = [](AppSettings &settings, const QString &key,
                           const QString &expected, const QString &selection) {
        QTimer::singleShot(0, [&] {
            auto *dialog = qobject_cast<QFileDialog *>(QApplication::activeModalWidget());
            assert(dialog && dialog->directory().absolutePath() == expected);
            if (selection.isEmpty()) dialog->reject();
            else {
                dialog->selectFile(selection);
                QMetaObject::invokeMethod(dialog, "accept", Qt::DirectConnection);
            }
        });
        assert(settings.chooseExportFolder(key, "Frame.png", nullptr) == selection);
    };
    {
        AppSettings settings;
        choose(settings, "fileA", fallback, first);
        choose(settings, "fileB", fallback, second);
        choose(settings, "fileA", first, ""); // Cancellation preserves the previous folder.
    }
    AppSettings reopened;
    choose(reopened, "fileA", first, first);
    choose(reopened, "fileB", second, second);

    const auto createExport = [](const QString &directory) {
        QFile file(directory + "/Frame.svg");
        assert(file.open(QIODevice::WriteOnly));
        file.write("<svg xmlns='http://www.w3.org/2000/svg' width='100' height='60'><rect width='100' height='60' fill='blue'/></svg>");
    };
    createExport(first);
    createExport(second);
    reopened.recordExport(first, "Frame.svg", "Source A", QUrl("https://www.figma.com/design/fileA"));
    reopened.recordExport(second, "Frame.svg", "Source B", QUrl("https://www.figma.com/design/fileB"));
    reopened.recordExport(first, "Frame.svg", "Source A", QUrl("https://www.figma.com/design/fileA"));
    assert(reopened.exportHistory().size() == 2);
    assert(reopened.exportHistory().first().toMap().value("path").toString() == first + "/Frame.svg");
    assert(reopened.exportHistory().first().toMap().value("fileType").toString() == "SVG");
    assert(reopened.exportHistory().first().toMap().value("originName").toString() == "Source A");
    {
        AppSettings historyReopened;
        assert(historyReopened.exportHistory().size() == 2);
        assert(historyReopened.deleteExport(first + "/Frame.svg"));
        assert(!QFileInfo::exists(first + "/Frame.svg"));
        assert(historyReopened.exportHistory().size() == 1);
        createExport(first);
        assert(!historyReopened.deleteExport(first + "/Frame.svg")); // Untracked files are never deleted.
        assert(QFileInfo::exists(first + "/Frame.svg"));
        historyReopened.clearExports();
        assert(historyReopened.exportHistory().isEmpty());
        assert(QFileInfo::exists(second + "/Frame.svg")); // Clearing keeps the files.
    }
    QDir(second).removeRecursively();
    choose(reopened, "fileB", fallback, ""); // Missing folders fall back safely.
    puts("Export folders, persistent history, deletion, and clearing checks passed");
}
