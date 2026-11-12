#include "temp_directory.h"

#include "media_io.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSettings>
#include <QSqlDatabase>
#include <QSqlQuery>
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

bool CTempDirectory::seed_schema_v1(const QString& directory) {
   if (!QDir().mkpath(directory)) {
      return false;
   }
   const QString name =
       QUuid::createUuid().toString(QUuid::WithoutBraces);
   QSqlDatabase database = QSqlDatabase::addDatabase("QSQLITE", name);
   database.setDatabaseName(QDir(directory).filePath("library.db"));
   if (!database.open()) {
      QSqlDatabase::removeDatabase(name);
      return false;
   }
   QSqlQuery query(database);
   const bool ok =
       query.exec("CREATE TABLE folders ("
                  "id TEXT PRIMARY KEY, parent_id TEXT, "
                  "name TEXT NOT NULL, prompt TEXT NOT NULL "
                  "DEFAULT '')") &&
       query.exec("CREATE TABLE shorts ("
                  "id TEXT PRIMARY KEY, folder_id TEXT NOT NULL, "
                  "name TEXT NOT NULL, status TEXT NOT NULL)") &&
       query.exec("INSERT INTO folders(id, parent_id, name, prompt) "
                  "VALUES('f1', '', 'Old', '')") &&
       query.exec("PRAGMA user_version = 1");
   database.close();
   QSqlDatabase::removeDatabase(name);
   return ok;
}

QString CTempDirectory::fixture_path(const QString& name) const {
   return QDir(QString::fromUtf8(QUICK_TEST_SOURCE_DIR))
       .filePath(QStringLiteral("fixtures/") + name);
}

bool CTempDirectory::file_exists(const QString& path) const {
   return QFileInfo::exists(path);
}

QString CTempDirectory::read_text(const QString& path) const {
   QFile file(path);
   if (!file.open(QIODevice::ReadOnly)) {
      return {};
   }
   return QString::fromUtf8(file.readAll());
}

int CTempDirectory::video_width(const QString& path) const {
   return CMediaIo::probe(path).width;
}

int CTempDirectory::video_height(const QString& path) const {
   return CMediaIo::probe(path).height;
}
