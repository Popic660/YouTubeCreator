#include "temp_directory.h"

#include "media_io.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
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

bool CTempDirectory::seed_schema_v2(const QString& directory) {
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
                  "name TEXT NOT NULL, status TEXT NOT NULL, "
                  "duration_ms INTEGER NOT NULL DEFAULT 0, "
                  "poster_relpath TEXT NOT NULL DEFAULT '')") &&
       query.exec("INSERT INTO folders(id, parent_id, name, prompt) "
                  "VALUES('f1', '', 'Old', '')") &&
       query.exec("INSERT INTO shorts(id, folder_id, name, status, "
                  "duration_ms, poster_relpath) "
                  "VALUES('s1', 'f1', 'Clip', 'draft', 1000, '')") &&
       query.exec("PRAGMA user_version = 2");
   database.close();
   QSqlDatabase::removeDatabase(name);
   if (!ok) {
      return false;
   }

   const QString media_dir =
       QDir(directory).filePath("media/a1");
   const QString short_dir =
       QDir(directory).filePath("shorts/s1");
   if (!QDir().mkpath(media_dir) || !QDir().mkpath(short_dir)) {
      return false;
   }
   const QString source = fixture_path("vertical-short.mp4");
   const QString dest =
       QDir(media_dir).filePath("vertical-short.mp4");
   if (!QFile::copy(source, dest)) {
      return false;
   }

   QJsonObject clip;
   clip["id"] = QStringLiteral("c1");
   clip["track"] = QStringLiteral("v1");
   clip["kind"] = QStringLiteral("video");
   clip["asset_id"] = QStringLiteral("a1");
   clip["file"] = QStringLiteral("media/a1/vertical-short.mp4");
   clip["in_ms"] = 0;
   clip["out_ms"] = 1000;
   clip["start_ms"] = 0;
   QJsonArray clips;
   clips.append(clip);
   QJsonObject root;
   root["version"] = 1;
   root["playhead_ms"] = 0;
   root["clips"] = clips;
   return write_text(QDir(short_dir).filePath("project.json"),
                     QString::fromUtf8(
                         QJsonDocument(root).toJson()));
}

QString CTempDirectory::make_image(const QString& directory) const {
   if (!QDir().mkpath(directory)) {
      return {};
   }
   QImage image(8, 8, QImage::Format_RGB32);
   image.fill(Qt::red);
   const QString path = QDir(directory).filePath("still.png");
   if (!image.save(path, "PNG")) {
      return {};
   }
   return path;
}

QString CTempDirectory::make_wav(const QString& directory) const {
   if (!QDir().mkpath(directory)) {
      return {};
   }
   const QString path = QDir(directory).filePath("tone.wav");
   QFile file(path);
   if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
      return {};
   }
   const int sample_rate = 8000;
   const int samples = 8000;
   const int data_size = samples * 2;
   const int chunk_size = 36 + data_size;
   QByteArray header;
   header.append("RIFF");
   header.append(reinterpret_cast<const char*>(&chunk_size), 4);
   header.append("WAVEfmt ");
   const int fmt_size = 16;
   const qint16 audio_format = 1;
   const qint16 channels = 1;
   const qint16 bits = 16;
   const int byte_rate = sample_rate * channels * bits / 8;
   const qint16 block_align = channels * bits / 8;
   header.append(reinterpret_cast<const char*>(&fmt_size), 4);
   header.append(reinterpret_cast<const char*>(&audio_format), 2);
   header.append(reinterpret_cast<const char*>(&channels), 2);
   header.append(reinterpret_cast<const char*>(&sample_rate), 4);
   header.append(reinterpret_cast<const char*>(&byte_rate), 4);
   header.append(reinterpret_cast<const char*>(&block_align), 2);
   header.append(reinterpret_cast<const char*>(&bits), 2);
   header.append("data");
   header.append(reinterpret_cast<const char*>(&data_size), 4);
   file.write(header);
   QByteArray pcm(data_size, 0);
   file.write(pcm);
   return path;
}

bool CTempDirectory::write_text(const QString& path,
                                const QString& text) const {
   QDir().mkpath(QFileInfo(path).absolutePath());
   QFile file(path);
   if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
      return false;
   }
   file.write(text.toUtf8());
   return true;
}

bool CTempDirectory::mkpath(const QString& path) const {
   return QDir().mkpath(path);
}

bool CTempDirectory::copy_file(const QString& source,
                               const QString& dest) const {
   QDir().mkpath(QFileInfo(dest).absolutePath());
   QFile::remove(dest);
   return QFile::copy(source, dest);
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
