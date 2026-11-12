#include "temp_directory.h"

#include <QDir>
#include <QSettings>
#include <QUuid>

CTempDirectory::CTempDirectory(QObject* parent) : QObject(parent) {}

QString CTempDirectory::make() {
   const QString path =
       QDir::tempPath() + "/yc-lib-" +
       QUuid::createUuid().toString(QUuid::Id128);
   QDir().mkpath(path);
   return path;
}

void CTempDirectory::remove_tree(const QString& path) {
   if (path.isEmpty()) {
      return;
   }
   QDir(path).removeRecursively();
}

void CTempDirectory::save_library_path(const QString& path) {
   QSettings settings;
   settings.setValue("library/path", path);
   settings.sync();
}

void CTempDirectory::clear_library_path() {
   QSettings settings;
   settings.remove("library/path");
   settings.sync();
}
