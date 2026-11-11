#include <QCoreApplication>
#include <QDir>
#include <QQuickStyle>
#include <QSettings>
#include <QtQuickTest>
#include <QtQml/qqmlextensionplugin.h>

Q_IMPORT_QML_PLUGIN(CreatorPlugin)

/**
 * @brief Запускает проверки главного окна.
 * @param argc - число аргументов.
 * @param argv - аргументы процесса.
 * @return код завершения теста.
 */
int main(int argc, char* argv[]) {
   QCoreApplication::setOrganizationName("YouTubeCreator");
   QCoreApplication::setApplicationName("MainWindow");
   const QString settings_dir =
      QDir::tempPath() + "/youtube-creator-shell-tests";
   QDir(settings_dir).removeRecursively();
   QDir().mkpath(settings_dir);
   QSettings::setDefaultFormat(QSettings::IniFormat);
   QSettings::setPath(
      QSettings::IniFormat, QSettings::UserScope, settings_dir);
   QQuickStyle::setStyle("Basic");
   return quick_test_main(
      argc, argv, "shell", QUICK_TEST_SOURCE_DIR);
}
