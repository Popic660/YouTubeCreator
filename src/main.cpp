#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QtQml/qqmlextensionplugin.h>

Q_IMPORT_QML_PLUGIN(CreatorPlugin)

/**
 * @brief Открывает главное окно.
 * @param argc - число аргументов командной строки.
 * @param argv - аргументы командной строки.
 * @return код завершения процесса.
 */
int main(int argc, char* argv[]) {
   QCoreApplication::setOrganizationName("YouTubeCreator");
   QCoreApplication::setApplicationName("MainWindow");
   QQuickStyle::setStyle("Basic");
   QGuiApplication application(argc, argv);
   QQmlApplicationEngine engine;
   QObject::connect(
      &engine,
      &QQmlApplicationEngine::objectCreationFailed,
      &application,
      [&application]() { application.exit(-1); },
      Qt::QueuedConnection);
   engine.loadFromModule("Creator", "Main");
   if (engine.rootObjects().isEmpty()) {
      return -1;
   }
   return application.exec();
}
