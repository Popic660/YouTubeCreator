#include "library_store.h"

#include "project_document.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QSettings>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QStringList>
#include <QUrl>
#include <QUuid>
#include <QVariant>

namespace {

constexpr int kSchemaVersion = 2;
constexpr char kPathKey[] = "library/path";
constexpr char kDraftStatus[] = "draft";

/**
 * @brief Превращает file-URL или путь в локальный каталог.
 * @param value - путь или URL.
 * @return очищенный локальный путь.
 */
QString local_directory(const QString& value) {
   const QUrl url(value);
   if (url.isLocalFile()) {
      return QDir::cleanPath(url.toLocalFile());
   }
   return QDir::cleanPath(value);
}

/**
 * @brief Оставляет имя без краевых пробелов.
 * @param name - введённое имя.
 * @return имя или пустая строка.
 */
QString clean_name(const QString& name) {
   return name.trimmed();
}

}  // namespace

CLibraryStore::CLibraryStore(QObject* parent) : QObject(parent) {}

CLibraryStore::~CLibraryStore() {
   opened_ = false;
   release_connection();
}

bool CLibraryStore::open(const QString& directory) {
   close();
   const QString path = local_directory(directory);
   if (!QFileInfo(path).isDir()) {
      return false;
   }

   connection_name_ =
       QUuid::createUuid().toString(QUuid::WithoutBraces);
   QSqlDatabase database =
       QSqlDatabase::addDatabase("QSQLITE", connection_name_);
   database.setDatabaseName(QDir(path).filePath("library.db"));
   if (!database.open()) {
      release_connection();
      return false;
   }

   const int version = read_user_version();
   if (version == 0) {
      if (!create_schema()) {
         database.close();
         database = QSqlDatabase();
         release_connection();
         return false;
      }
   } else if (version == 1) {
      if (!migrate_from_v1()) {
         database.close();
         database = QSqlDatabase();
         release_connection();
         return false;
      }
   } else if (version != kSchemaVersion) {
      database.close();
      database = QSqlDatabase();
      release_connection();
      return false;
   }

   opened_ = true;
   root_path_ = path;
   emit open_changed();
   emit library_changed();
   return true;
}

void CLibraryStore::close() {
   const bool was_open = opened_;
   opened_ = false;
   root_path_.clear();
   release_connection();
   if (was_open) {
      emit open_changed();
      emit library_changed();
   }
}

bool CLibraryStore::open_saved() {
   QSettings settings;
   const QString path = settings.value(kPathKey).toString();
   if (path.isEmpty()) {
      return false;
   }
   return open(path);
}

void CLibraryStore::remember() {
   if (!opened_ || root_path_.isEmpty()) {
      return;
   }
   save_path(root_path_);
}

void CLibraryStore::save_path(const QString& directory) {
   const QString path = local_directory(directory);
   QSettings settings;
   settings.setValue(kPathKey, path);
   settings.sync();
}

void CLibraryStore::clear_saved_path() {
   QSettings settings;
   settings.remove(kPathKey);
   settings.sync();
}

int CLibraryStore::user_version() const {
   if (!opened_) {
      return -1;
   }
   return read_user_version();
}

bool CLibraryStore::schema_contains(const QString& name) const {
   if (!opened_) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("SELECT 1 FROM sqlite_master WHERE name = ?");
   query.addBindValue(name);
   if (!query.exec()) {
      return false;
   }
   return query.next();
}

QString CLibraryStore::create_folder(const QString& parent_id,
                                     const QString& name) {
   const QString clean = clean_name(name);
   if (!opened_ || clean.isEmpty()) {
      return {};
   }
   if (!parent_id.isEmpty() && !folder_exists(parent_id)) {
      return {};
   }

   const QString id =
       QUuid::createUuid().toString(QUuid::WithoutBraces);
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare(
       "INSERT INTO folders (id, parent_id, name, prompt) "
       "VALUES (?, ?, ?, '')");
   query.addBindValue(id);
   if (parent_id.isEmpty()) {
      query.addBindValue(QVariant());
   } else {
      query.addBindValue(parent_id);
   }
   query.addBindValue(clean);
   if (!query.exec()) {
      return {};
   }
   notify_changed();
   return id;
}

QString CLibraryStore::folder_name(const QString& id) const {
   for (const LibraryFolder& folder : folders()) {
      if (folder.id == id) {
         return folder.name;
      }
   }
   return {};
}

QString CLibraryStore::folder_parent(const QString& id) const {
   for (const LibraryFolder& folder : folders()) {
      if (folder.id == id) {
         return folder.parent_id;
      }
   }
   return {};
}

bool CLibraryStore::rename_folder(const QString& id,
                                  const QString& name) {
   const QString clean = clean_name(name);
   if (!opened_ || clean.isEmpty() || !folder_exists(id)) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("UPDATE folders SET name = ? WHERE id = ?");
   query.addBindValue(clean);
   query.addBindValue(id);
   if (!query.exec() || query.numRowsAffected() == 0) {
      return false;
   }
   notify_changed();
   return true;
}

QString CLibraryStore::folder_prompt(const QString& id) const {
   for (const LibraryFolder& folder : folders()) {
      if (folder.id == id) {
         return folder.prompt;
      }
   }
   return {};
}

bool CLibraryStore::set_folder_prompt(const QString& id,
                                      const QString& prompt) {
   if (!opened_ || !folder_exists(id)) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("UPDATE folders SET prompt = ? WHERE id = ?");
   query.addBindValue(prompt);
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

QString CLibraryStore::effective_prompt(const QString& id) const {
   std::vector<QString> chain;
   QString current = id;
   QSet<QString> seen;
   while (!current.isEmpty()) {
      if (seen.contains(current)) {
         break;
      }
      seen.insert(current);
      bool found = false;
      for (const LibraryFolder& folder : folders()) {
         if (folder.id != current) {
            continue;
         }
         chain.push_back(folder.prompt);
         current = folder.parent_id;
         found = true;
         break;
      }
      if (!found) {
         break;
      }
   }

   QStringList parts;
   for (auto it = chain.rbegin(); it != chain.rend(); ++it) {
      if (!it->isEmpty()) {
         parts.append(*it);
      }
   }
   return parts.join("\n\n");
}

bool CLibraryStore::folder_needs_confirmation(
    const QString& id) const {
   if (!folder_exists(id)) {
      return false;
   }
   const std::vector<QString> ids = subtree_ids(id);
   for (const LibraryShort& clip : shorts()) {
      for (const QString& folder_id : ids) {
         if (clip.folder_id == folder_id) {
            return true;
         }
      }
   }
   return false;
}

bool CLibraryStore::delete_folder(const QString& id, bool confirmed) {
   if (!opened_ || !folder_exists(id)) {
      return false;
   }
   if (folder_needs_confirmation(id) && !confirmed) {
      return false;
   }

   const std::vector<QString> folder_ids = subtree_ids(id);
   QSqlDatabase database = QSqlDatabase::database(connection_name_);
   if (!database.transaction()) {
      return false;
   }

   for (const QString& folder_id : folder_ids) {
      QSqlQuery query(database);
      query.prepare("DELETE FROM shorts WHERE folder_id = ?");
      query.addBindValue(folder_id);
      if (!query.exec()) {
         database.rollback();
         return false;
      }
   }
   for (const QString& folder_id : folder_ids) {
      QSqlQuery query(database);
      query.prepare("DELETE FROM folders WHERE id = ?");
      query.addBindValue(folder_id);
      if (!query.exec()) {
         database.rollback();
         return false;
      }
   }
   if (!database.commit()) {
      database.rollback();
      return false;
   }
   notify_changed();
   return true;
}

QString CLibraryStore::create_short(const QString& folder_id,
                                    const QString& name) {
   const QString clean = clean_name(name);
   if (!opened_ || clean.isEmpty() || !folder_exists(folder_id)) {
      return {};
   }
   const QString id =
       QUuid::createUuid().toString(QUuid::WithoutBraces);
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare(
       "INSERT INTO shorts (id, folder_id, name, status) "
       "VALUES (?, ?, ?, ?)");
   query.addBindValue(id);
   query.addBindValue(folder_id);
   query.addBindValue(clean);
   query.addBindValue(QString::fromLatin1(kDraftStatus));
   if (!query.exec()) {
      return {};
   }
   notify_changed();
   return id;
}

QString CLibraryStore::short_name(const QString& id) const {
   for (const LibraryShort& clip : shorts()) {
      if (clip.id == id) {
         return clip.name;
      }
   }
   return {};
}

QString CLibraryStore::short_folder(const QString& id) const {
   for (const LibraryShort& clip : shorts()) {
      if (clip.id == id) {
         return clip.folder_id;
      }
   }
   return {};
}

QString CLibraryStore::short_status(const QString& id) const {
   for (const LibraryShort& clip : shorts()) {
      if (clip.id == id) {
         return clip.status;
      }
   }
   return {};
}

bool CLibraryStore::short_has_poster(const QString& id) const {
   return !short_poster_path(id).isEmpty();
}

qint64 CLibraryStore::short_duration_ms(const QString& id) const {
   for (const LibraryShort& clip : shorts()) {
      if (clip.id == id) {
         return clip.duration_ms;
      }
   }
   return 0;
}

QString CLibraryStore::short_poster_path(const QString& id) const {
   for (const LibraryShort& clip : shorts()) {
      if (clip.id == id && !clip.poster_relpath.isEmpty()) {
         const QString path =
             QDir(root_path_).filePath(clip.poster_relpath);
         if (QFileInfo::exists(path)) {
            return path;
         }
      }
   }
   return {};
}

bool CLibraryStore::update_short_media(
    const QString& id, qint64 duration_ms,
    const QString& poster_relpath) {
   if (!opened_ || short_name(id).isEmpty()) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare(
       "UPDATE shorts SET duration_ms = ?, poster_relpath = ? "
       "WHERE id = ?");
   query.addBindValue(duration_ms);
   query.addBindValue(poster_relpath);
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

QString CLibraryStore::import_video(const QString& folder_id,
                                    const QString& path) {
   CProjectDocument document;
   document.set_store(this);
   return document.import_video(folder_id, path);
}

bool CLibraryStore::import_into_short(const QString& short_id,
                                      const QString& path) {
   CProjectDocument document;
   document.set_store(this);
   return document.import_into_short(short_id, path);
}

bool CLibraryStore::rename_short(const QString& id,
                                 const QString& name) {
   const QString clean = clean_name(name);
   if (!opened_ || clean.isEmpty() || short_name(id).isEmpty()) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("UPDATE shorts SET name = ? WHERE id = ?");
   query.addBindValue(clean);
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

bool CLibraryStore::short_needs_confirmation(
    const QString& id) const {
   return !short_name(id).isEmpty();
}

bool CLibraryStore::delete_short(const QString& id, bool confirmed) {
   if (!opened_ || short_name(id).isEmpty() || !confirmed) {
      return false;
   }
   remove_short_files(id);
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("DELETE FROM shorts WHERE id = ?");
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

bool CLibraryStore::move_short(const QString& id,
                               const QString& folder_id) {
   if (!opened_ || short_name(id).isEmpty() ||
       !folder_exists(folder_id)) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("UPDATE shorts SET folder_id = ? WHERE id = ?");
   query.addBindValue(folder_id);
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

bool CLibraryStore::reparent_folder(const QString& id,
                                    const QString& parent_id) {
   if (!opened_ || !folder_exists(id)) {
      return false;
   }
   if (!parent_id.isEmpty() && !folder_exists(parent_id)) {
      return false;
   }
   if (is_in_subtree(parent_id, id)) {
      return false;
   }
   if (folder_parent(id) == parent_id) {
      return true;
   }

   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("UPDATE folders SET parent_id = ? WHERE id = ?");
   if (parent_id.isEmpty()) {
      query.addBindValue(QVariant());
   } else {
      query.addBindValue(parent_id);
   }
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

std::vector<LibraryFolder> CLibraryStore::folders() const {
   std::vector<LibraryFolder> result;
   if (!opened_) {
      return result;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   if (!query.exec(
           "SELECT id, parent_id, name, prompt FROM folders")) {
      return result;
   }
   while (query.next()) {
      LibraryFolder folder;
      folder.id = query.value(0).toString();
      folder.parent_id = query.value(1).toString();
      folder.name = query.value(2).toString();
      folder.prompt = query.value(3).toString();
      result.push_back(folder);
   }
   return result;
}

std::vector<LibraryShort> CLibraryStore::shorts() const {
   std::vector<LibraryShort> result;
   if (!opened_) {
      return result;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   if (!query.exec("SELECT id, folder_id, name, status, "
                   "duration_ms, poster_relpath FROM shorts")) {
      return result;
   }
   while (query.next()) {
      LibraryShort clip;
      clip.id = query.value(0).toString();
      clip.folder_id = query.value(1).toString();
      clip.name = query.value(2).toString();
      clip.status = query.value(3).toString();
      clip.duration_ms = query.value(4).toLongLong();
      clip.poster_relpath = query.value(5).toString();
      result.push_back(clip);
   }
   return result;
}

bool CLibraryStore::create_schema() {
   QSqlDatabase database = QSqlDatabase::database(connection_name_);
   if (!database.transaction()) {
      return false;
   }
   QSqlQuery query(database);
   const QStringList statements = {
       "CREATE TABLE IF NOT EXISTS folders ("
       "id TEXT PRIMARY KEY, parent_id TEXT, "
       "name TEXT NOT NULL, prompt TEXT NOT NULL DEFAULT '')",
       "CREATE INDEX IF NOT EXISTS folders_name ON folders(name)",
       "CREATE TABLE IF NOT EXISTS shorts ("
       "id TEXT PRIMARY KEY, folder_id TEXT NOT NULL, "
       "name TEXT NOT NULL, status TEXT NOT NULL, "
       "duration_ms INTEGER NOT NULL DEFAULT 0, "
       "poster_relpath TEXT NOT NULL DEFAULT '')",
       "CREATE INDEX IF NOT EXISTS shorts_name ON shorts(name)",
       "CREATE INDEX IF NOT EXISTS shorts_folder "
       "ON shorts(folder_id)",
       "PRAGMA user_version = 2",
   };
   for (const QString& statement : statements) {
      if (!query.exec(statement)) {
         database.rollback();
         return false;
      }
   }
   return database.commit();
}

bool CLibraryStore::migrate_from_v1() {
   QSqlDatabase database = QSqlDatabase::database(connection_name_);
   QSqlQuery query(database);
   if (!query.exec("ALTER TABLE shorts ADD COLUMN duration_ms "
                   "INTEGER NOT NULL DEFAULT 0")) {
      return false;
   }
   if (!query.exec("ALTER TABLE shorts ADD COLUMN poster_relpath "
                   "TEXT NOT NULL DEFAULT ''")) {
      return false;
   }
   return query.exec("PRAGMA user_version = 2");
}

void CLibraryStore::remove_short_files(const QString& id) {
   const QString folder = QDir(root_path_).filePath("shorts/" + id);
   QStringList assets;
   const QString json_path = QDir(folder).filePath("project.json");
   QFile json_file(json_path);
   if (json_file.open(QIODevice::ReadOnly)) {
      const QJsonArray clips =
          QJsonDocument::fromJson(json_file.readAll())
              .object()
              .value("clips")
              .toArray();
      for (const QJsonValue& value : clips) {
         const QString rel = value.toObject().value("file").toString();
         if (!rel.isEmpty()) {
            assets.append(rel);
         }
      }
   }
   json_file.close();
   QFile::remove(json_path);
   QDir(folder).removeRecursively();
   for (const QString& rel : assets) {
      bool used = false;
      for (const LibraryShort& clip : shorts()) {
         if (clip.id == id) {
            continue;
         }
         QFile other(QDir(root_path_).filePath(
             "shorts/" + clip.id + "/project.json"));
         if (!other.open(QIODevice::ReadOnly)) {
            continue;
         }
         const QString text = QString::fromUtf8(other.readAll());
         if (text.contains(rel)) {
            used = true;
            break;
         }
      }
      if (!used) {
         const QString abs = QDir(root_path_).filePath(rel);
         QFile::remove(abs);
         QDir().rmdir(QFileInfo(abs).absolutePath());
      }
   }
}

int CLibraryStore::read_user_version() const {
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   if (!query.exec("PRAGMA user_version") || !query.next()) {
      return -1;
   }
   return query.value(0).toInt();
}

void CLibraryStore::release_connection() {
   const QString name = connection_name_;
   if (name.isEmpty()) {
      return;
   }
   {
      QSqlDatabase database = QSqlDatabase::database(name, false);
      if (database.isValid()) {
         database.close();
      }
   }
   QSqlDatabase::removeDatabase(name);
   connection_name_.clear();
}

bool CLibraryStore::folder_exists(const QString& id) const {
   return !folder_name(id).isEmpty();
}

std::vector<QString> CLibraryStore::subtree_ids(
    const QString& root_id) const {
   std::vector<QString> ids;
   QSet<QString> seen;
   std::vector<QString> pending;
   pending.push_back(root_id);
   const std::vector<LibraryFolder> all = folders();
   while (!pending.empty()) {
      const QString current = pending.back();
      pending.pop_back();
      if (seen.contains(current)) {
         continue;
      }
      seen.insert(current);
      ids.push_back(current);
      for (const LibraryFolder& folder : all) {
         if (folder.parent_id == current) {
            pending.push_back(folder.id);
         }
      }
   }
   return ids;
}

bool CLibraryStore::is_in_subtree(const QString& node,
                                  const QString& ancestor) const {
   if (node.isEmpty()) {
      return false;
   }
   QString current = node;
   QSet<QString> seen;
   while (!current.isEmpty()) {
      if (current == ancestor) {
         return true;
      }
      if (seen.contains(current)) {
         return false;
      }
      seen.insert(current);
      current = folder_parent(current);
   }
   return false;
}

void CLibraryStore::notify_changed() {
   emit library_changed();
}
