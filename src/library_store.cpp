#include "library_store.h"

#include "media_io.h"
#include "project_document.h"

#include <QDir>
#include <QDirIterator>
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

#include <algorithm>

namespace {

constexpr int kSchemaVersion = 3;
constexpr char kPathKey[] = "library/path";
constexpr char kDraftStatus[] = "draft";
constexpr char kRootBinId[] = "root";
constexpr qint64 kImageDurationMs = 5000;

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

   root_path_ = path;
   opened_ = true;
   const int version = read_user_version();
   bool migrated = true;
   if (version == 0) {
      migrated = create_schema();
   } else if (version == 1) {
      migrated = migrate_from_v1() && migrate_from_v2();
   } else if (version == 2) {
      migrated = migrate_from_v2();
   } else if (version != kSchemaVersion) {
      migrated = false;
   }
   if (!migrated) {
      opened_ = false;
      root_path_.clear();
      database.close();
      database = QSqlDatabase();
      release_connection();
      return false;
   }

   emit open_changed();
   emit library_changed();
   return true;
}

void CLibraryStore::close() {
   const bool was_open = opened_;
   opened_ = false;
   root_path_.clear();
   last_error_.clear();
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

QString CLibraryStore::root_bin_id() const {
   if (!opened_) {
      return {};
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   if (!query.exec("SELECT id FROM bins WHERE parent_id IS NULL "
                   "LIMIT 1") ||
       !query.next()) {
      return QString::fromLatin1(kRootBinId);
   }
   return query.value(0).toString();
}

QString CLibraryStore::create_bin(const QString& parent_id,
                                  const QString& name) {
   const QString clean = clean_name(name);
   const QString parent = resolved_bin_id(parent_id);
   if (!opened_ || clean.isEmpty() || !bin_exists(parent)) {
      return {};
   }
   const QString id =
       QUuid::createUuid().toString(QUuid::WithoutBraces);
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare(
       "INSERT INTO bins (id, parent_id, name) VALUES (?, ?, ?)");
   query.addBindValue(id);
   query.addBindValue(parent);
   query.addBindValue(clean);
   if (!query.exec()) {
      return {};
   }
   notify_changed();
   return id;
}

QString CLibraryStore::bin_name(const QString& id) const {
   for (const LibraryBin& bin : bins()) {
      if (bin.id == id) {
         return bin.name;
      }
   }
   return {};
}

QString CLibraryStore::bin_parent(const QString& id) const {
   for (const LibraryBin& bin : bins()) {
      if (bin.id == id) {
         return bin.parent_id;
      }
   }
   return {};
}

bool CLibraryStore::rename_bin(const QString& id,
                               const QString& name) {
   const QString clean = clean_name(name);
   if (!opened_ || clean.isEmpty() || !bin_exists(id) ||
       id == QLatin1String(kRootBinId)) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("UPDATE bins SET name = ? WHERE id = ?");
   query.addBindValue(clean);
   query.addBindValue(id);
   if (!query.exec() || query.numRowsAffected() == 0) {
      return false;
   }
   notify_changed();
   return true;
}

bool CLibraryStore::reparent_bin(const QString& id,
                                 const QString& parent_id) {
   const QString parent = resolved_bin_id(parent_id);
   if (!opened_ || !bin_exists(id) || !bin_exists(parent) ||
       id == QLatin1String(kRootBinId)) {
      return false;
   }
   if (is_in_bin_subtree(parent, id)) {
      return false;
   }
   if (bin_parent(id) == parent) {
      return true;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("UPDATE bins SET parent_id = ? WHERE id = ?");
   query.addBindValue(parent);
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

bool CLibraryStore::delete_bin(const QString& id) {
   if (!opened_ || !bin_exists(id) ||
       id == QLatin1String(kRootBinId)) {
      return false;
   }
   for (const LibraryBin& bin : bins()) {
      if (bin.parent_id == id) {
         return false;
      }
   }
   for (const LibraryAsset& asset : assets()) {
      if (asset.bin_id == id) {
         return false;
      }
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("DELETE FROM bins WHERE id = ?");
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

QString CLibraryStore::asset_name(const QString& id) const {
   return asset_by_id(id).name;
}

QString CLibraryStore::asset_kind(const QString& id) const {
   return asset_by_id(id).kind;
}

QString CLibraryStore::asset_bin(const QString& id) const {
   return asset_by_id(id).bin_id;
}

QString CLibraryStore::asset_relpath(const QString& id) const {
   return asset_by_id(id).relpath;
}

QString CLibraryStore::asset_abs_path(const QString& id) const {
   const QString rel = asset_relpath(id);
   if (rel.isEmpty() || root_path_.isEmpty()) {
      return {};
   }
   return QDir(root_path_).filePath(rel);
}

qint64 CLibraryStore::asset_duration_ms(const QString& id) const {
   return asset_by_id(id).duration_ms;
}

qint64 CLibraryStore::asset_in_ms(const QString& id) const {
   return asset_by_id(id).in_ms;
}

qint64 CLibraryStore::asset_out_ms(const QString& id) const {
   return asset_by_id(id).out_ms;
}

bool CLibraryStore::set_asset_marks(const QString& id, qint64 in_ms,
                                    qint64 out_ms) {
   const LibraryAsset asset = asset_by_id(id);
   if (!opened_ || asset.id.isEmpty()) {
      return false;
   }
   const qint64 duration = asset.duration_ms;
   const qint64 in_clamped = std::max<qint64>(in_ms, 0);
   qint64 out_clamped = out_ms;
   if (duration > 0) {
      out_clamped = std::min(out_clamped, duration);
   }
   if (out_clamped <= in_clamped) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("UPDATE assets SET in_ms = ?, out_ms = ? "
                 "WHERE id = ?");
   query.addBindValue(in_clamped);
   query.addBindValue(out_clamped);
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

bool CLibraryStore::move_asset(const QString& id,
                               const QString& bin_id) {
   const QString bin = resolved_bin_id(bin_id);
   if (!opened_ || asset_by_id(id).id.isEmpty() || !bin_exists(bin)) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("UPDATE assets SET bin_id = ? WHERE id = ?");
   query.addBindValue(bin);
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   notify_changed();
   return true;
}

bool CLibraryStore::delete_asset(const QString& id, bool confirmed) {
   set_last_error({});
   const LibraryAsset asset = asset_by_id(id);
   if (!opened_ || asset.id.isEmpty()) {
      return false;
   }
   if (!confirmed) {
      return false;
   }
   if (asset_is_busy(id)) {
      set_last_error(QStringLiteral("busy"));
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare("DELETE FROM assets WHERE id = ?");
   query.addBindValue(id);
   if (!query.exec()) {
      return false;
   }
   bool shared = false;
   for (const LibraryAsset& other : assets()) {
      if (other.relpath == asset.relpath) {
         shared = true;
         break;
      }
   }
   if (!shared && !asset.relpath.isEmpty()) {
      const QString abs =
          QDir(root_path_).filePath(asset.relpath);
      QFile::remove(abs);
      QDir().rmdir(QFileInfo(abs).absolutePath());
   }
   notify_changed();
   return true;
}

bool CLibraryStore::asset_is_busy(const QString& id) const {
   if (id.isEmpty() || !opened_) {
      return false;
   }
   for (const LibraryShort& clip : shorts()) {
      QFile file(QDir(root_path_).filePath(
          "shorts/" + clip.id + "/project.json"));
      if (!file.open(QIODevice::ReadOnly)) {
         continue;
      }
      const QJsonArray clips =
          QJsonDocument::fromJson(file.readAll())
              .object()
              .value("clips")
              .toArray();
      for (const QJsonValue& value : clips) {
         if (value.toObject().value("asset_id").toString() == id) {
            return true;
         }
      }
   }
   return false;
}

int CLibraryStore::asset_count() const {
   return static_cast<int>(assets().size());
}

int CLibraryStore::media_file_count() const {
   if (!opened_ || root_path_.isEmpty()) {
      return 0;
   }
   int count = 0;
   QDirIterator it(QDir(root_path_).filePath("media"), QDir::Files,
                   QDirIterator::Subdirectories);
   while (it.hasNext()) {
      it.next();
      ++count;
   }
   return count;
}

int CLibraryStore::short_count() const {
   return static_cast<int>(shorts().size());
}

int CLibraryStore::bin_count() const {
   return static_cast<int>(bins().size());
}

std::vector<LibraryBin> CLibraryStore::bins() const {
   std::vector<LibraryBin> result;
   if (!opened_) {
      return result;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   if (!query.exec("SELECT id, parent_id, name FROM bins")) {
      return result;
   }
   while (query.next()) {
      LibraryBin bin;
      bin.id = query.value(0).toString();
      bin.parent_id = query.value(1).toString();
      bin.name = query.value(2).toString();
      result.push_back(bin);
   }
   return result;
}

std::vector<LibraryAsset> CLibraryStore::assets() const {
   std::vector<LibraryAsset> result;
   if (!opened_) {
      return result;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   if (!query.exec("SELECT id, bin_id, name, kind, relpath, "
                   "duration_ms, in_ms, out_ms, fingerprint, size "
                   "FROM assets")) {
      return result;
   }
   while (query.next()) {
      LibraryAsset asset;
      asset.id = query.value(0).toString();
      asset.bin_id = query.value(1).toString();
      asset.name = query.value(2).toString();
      asset.kind = query.value(3).toString();
      asset.relpath = query.value(4).toString();
      asset.duration_ms = query.value(5).toLongLong();
      asset.in_ms = query.value(6).toLongLong();
      asset.out_ms = query.value(7).toLongLong();
      asset.fingerprint = query.value(8).toString();
      asset.size = query.value(9).toLongLong();
      result.push_back(asset);
   }
   return result;
}

LibraryAsset CLibraryStore::asset_by_id(const QString& id) const {
   for (const LibraryAsset& asset : assets()) {
      if (asset.id == id) {
         return asset;
      }
   }
   return {};
}

QString CLibraryStore::bin_by_name(const QString& name) const {
   for (const LibraryBin& bin : bins()) {
      if (bin.name == name) {
         return bin.id;
      }
   }
   return {};
}

QString CLibraryStore::asset_by_name(const QString& name) const {
   for (const LibraryAsset& asset : assets()) {
      if (asset.name == name) {
         return asset.id;
      }
   }
   return {};
}

QString CLibraryStore::import_media(const QString& bin_id,
                                    const QString& path) {
   set_last_error({});
   if (!opened_) {
      return {};
   }
   const QUrl url(path);
   const QString file = url.isLocalFile() ? url.toLocalFile()
                                          : QDir::cleanPath(path);
   if (file.isEmpty() || !QFileInfo::exists(file) ||
       QFileInfo(file).isDir()) {
      return {};
   }
   const QString bin = resolved_bin_id(bin_id);
   if (!bin_exists(bin)) {
      return {};
   }
   QString kind = CMediaIo::media_kind(file);
   if (kind.isEmpty()) {
      return {};
   }
   qint64 size = 0;
   const QString fingerprint =
       CMediaIo::file_fingerprint(file, &size);
   if (!fingerprint.isEmpty()) {
      for (const LibraryAsset& asset : assets()) {
         if (asset.fingerprint == fingerprint &&
             asset.bin_id == bin) {
            return asset.id;
         }
      }
      const QString existing =
          asset_id_by_fingerprint(fingerprint);
      if (!existing.isEmpty()) {
         const LibraryAsset source = asset_by_id(existing);
         const QString id =
             QUuid::createUuid().toString(QUuid::WithoutBraces);
         QSqlQuery query(QSqlDatabase::database(connection_name_));
         query.prepare(
             "INSERT INTO assets (id, bin_id, name, kind, relpath, "
             "duration_ms, in_ms, out_ms, fingerprint, size) "
             "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
         query.addBindValue(id);
         query.addBindValue(bin);
         query.addBindValue(source.name);
         query.addBindValue(source.kind);
         query.addBindValue(source.relpath);
         query.addBindValue(source.duration_ms);
         query.addBindValue(source.in_ms);
         query.addBindValue(source.out_ms);
         query.addBindValue(source.fingerprint);
         query.addBindValue(source.size);
         if (!query.exec()) {
            return {};
         }
         notify_changed();
         return id;
      }
   }

   const MediaInfo info = CMediaIo::probe(file);
   qint64 duration = info.duration_ms;
   if (kind == QLatin1String("image") && duration <= 0) {
      duration = kImageDurationMs;
   }
   if (kind == QLatin1String("audio") && duration <= 0) {
      duration = 1000;
   }
   if (kind == QLatin1String("video") && duration <= 0) {
      return {};
   }
   const QString id =
       QUuid::createUuid().toString(QUuid::WithoutBraces);
   const QString relative =
       CMediaIo::copy_asset(root_path_, file, id);
   if (relative.isEmpty()) {
      return {};
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare(
       "INSERT INTO assets (id, bin_id, name, kind, relpath, "
       "duration_ms, in_ms, out_ms, fingerprint, size) "
       "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?)");
   query.addBindValue(id);
   query.addBindValue(bin);
   query.addBindValue(QFileInfo(file).completeBaseName());
   query.addBindValue(kind);
   query.addBindValue(relative);
   query.addBindValue(duration);
   query.addBindValue(duration);
   query.addBindValue(fingerprint);
   query.addBindValue(size);
   if (!query.exec()) {
      QFile::remove(QDir(root_path_).filePath(relative));
      QDir().rmdir(QFileInfo(QDir(root_path_).filePath(relative))
                       .absolutePath());
      return {};
   }
   notify_changed();
   return id;
}

QString CLibraryStore::import_folder(const QString& bin_id,
                                     const QString& path) {
   if (!opened_) {
      return {};
   }
   const QUrl url(path);
   const QString folder = url.isLocalFile() ? url.toLocalFile()
                                            : QDir::cleanPath(path);
   const QFileInfo info(folder);
   if (!info.isDir()) {
      return {};
   }
   const QString parent = resolved_bin_id(bin_id);
   const QString created = create_bin(parent, info.fileName());
   if (created.isEmpty()) {
      return {};
   }
   const QFileInfoList entries =
       QDir(folder).entryInfoList(QDir::Files | QDir::Dirs |
                                      QDir::NoDotAndDotDot,
                                  QDir::Name);
   for (const QFileInfo& entry : entries) {
      if (entry.fileName().startsWith('.')) {
         continue;
      }
      if (entry.isDir()) {
         import_folder(created, entry.absoluteFilePath());
      } else {
         import_media(created, entry.absoluteFilePath());
      }
   }
   return created;
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
       "CREATE TABLE IF NOT EXISTS bins ("
       "id TEXT PRIMARY KEY, parent_id TEXT, "
       "name TEXT NOT NULL)",
       "CREATE INDEX IF NOT EXISTS bins_parent ON bins(parent_id)",
       "CREATE TABLE IF NOT EXISTS assets ("
       "id TEXT PRIMARY KEY, bin_id TEXT NOT NULL, "
       "name TEXT NOT NULL, kind TEXT NOT NULL, "
       "relpath TEXT NOT NULL, "
       "duration_ms INTEGER NOT NULL DEFAULT 0, "
       "in_ms INTEGER NOT NULL DEFAULT 0, "
       "out_ms INTEGER NOT NULL DEFAULT 0, "
       "fingerprint TEXT NOT NULL DEFAULT '', "
       "size INTEGER NOT NULL DEFAULT 0)",
       "CREATE INDEX IF NOT EXISTS assets_bin ON assets(bin_id)",
       "CREATE INDEX IF NOT EXISTS assets_fp "
       "ON assets(fingerprint)",
       "INSERT OR IGNORE INTO bins(id, parent_id, name) "
       "VALUES('root', NULL, 'Медиа')",
       "PRAGMA user_version = 3",
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

bool CLibraryStore::migrate_from_v2() {
   if (!ensure_pool_tables() || !ensure_root_bin()) {
      return false;
   }
   if (!register_assets_from_projects()) {
      return false;
   }
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   return query.exec("PRAGMA user_version = 3");
}

bool CLibraryStore::ensure_pool_tables() {
   QSqlDatabase database = QSqlDatabase::database(connection_name_);
   QSqlQuery query(database);
   const QStringList statements = {
       "CREATE TABLE IF NOT EXISTS bins ("
       "id TEXT PRIMARY KEY, parent_id TEXT, "
       "name TEXT NOT NULL)",
       "CREATE INDEX IF NOT EXISTS bins_parent ON bins(parent_id)",
       "CREATE TABLE IF NOT EXISTS assets ("
       "id TEXT PRIMARY KEY, bin_id TEXT NOT NULL, "
       "name TEXT NOT NULL, kind TEXT NOT NULL, "
       "relpath TEXT NOT NULL, "
       "duration_ms INTEGER NOT NULL DEFAULT 0, "
       "in_ms INTEGER NOT NULL DEFAULT 0, "
       "out_ms INTEGER NOT NULL DEFAULT 0, "
       "fingerprint TEXT NOT NULL DEFAULT '', "
       "size INTEGER NOT NULL DEFAULT 0)",
       "CREATE INDEX IF NOT EXISTS assets_bin ON assets(bin_id)",
       "CREATE INDEX IF NOT EXISTS assets_fp "
       "ON assets(fingerprint)",
   };
   for (const QString& statement : statements) {
      if (!query.exec(statement)) {
         return false;
      }
   }
   return true;
}

bool CLibraryStore::ensure_root_bin() {
   QSqlQuery query(QSqlDatabase::database(connection_name_));
   query.prepare(
       "INSERT OR IGNORE INTO bins(id, parent_id, name) "
       "VALUES(?, NULL, ?)");
   query.addBindValue(QString::fromLatin1(kRootBinId));
   query.addBindValue(QStringLiteral("Медиа"));
   return query.exec();
}

bool CLibraryStore::register_assets_from_projects() {
   const QString root = root_bin_id();
   if (root.isEmpty()) {
      return false;
   }
   QDirIterator json_files(
       QDir(root_path_).filePath("shorts"),
       QStringList{QStringLiteral("project.json")},
       QDir::Files, QDirIterator::Subdirectories);
   while (json_files.hasNext()) {
      QFile file(json_files.next());
      if (!file.open(QIODevice::ReadOnly)) {
         continue;
      }
      const QJsonArray clips =
          QJsonDocument::fromJson(file.readAll())
              .object()
              .value("clips")
              .toArray();
      for (const QJsonValue& value : clips) {
         const QJsonObject item = value.toObject();
         const QString asset_id = item.value("asset_id").toString();
         const QString rel = item.value("file").toString();
         if (asset_id.isEmpty() || rel.isEmpty()) {
            continue;
         }
         if (!asset_by_id(asset_id).id.isEmpty()) {
            continue;
         }
         const QString abs = QDir(root_path_).filePath(rel);
         qint64 size = 0;
         const QString fingerprint =
             CMediaIo::file_fingerprint(abs, &size);
         QString kind = item.value("kind").toString();
         if (kind.isEmpty() || kind == QLatin1String("text")) {
            kind = CMediaIo::media_kind(abs);
         }
         if (kind.isEmpty()) {
            kind = QStringLiteral("video");
         }
         qint64 duration = item.value("out_ms").toInteger() -
                           item.value("in_ms").toInteger();
         if (duration <= 0) {
            duration = CMediaIo::probe(abs).duration_ms;
         }
         QSqlQuery query(QSqlDatabase::database(connection_name_));
         query.prepare(
             "INSERT INTO assets (id, bin_id, name, kind, relpath, "
             "duration_ms, in_ms, out_ms, fingerprint, size) "
             "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?)");
         query.addBindValue(asset_id);
         query.addBindValue(root);
         query.addBindValue(QFileInfo(rel).completeBaseName());
         query.addBindValue(kind);
         query.addBindValue(rel);
         query.addBindValue(duration);
         query.addBindValue(duration);
         query.addBindValue(fingerprint);
         query.addBindValue(size);
         if (!query.exec()) {
            return false;
         }
      }
   }
   return true;
}

void CLibraryStore::remove_short_files(const QString& id) {
   const QString folder = QDir(root_path_).filePath("shorts/" + id);
   QStringList relpaths;
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
            relpaths.append(rel);
         }
      }
   }
   json_file.close();
   QFile::remove(json_path);
   QDir(folder).removeRecursively();
   for (const QString& rel : relpaths) {
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
         for (const LibraryAsset& asset : assets()) {
            if (asset.relpath == rel) {
               used = true;
               break;
            }
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

bool CLibraryStore::bin_exists(const QString& id) const {
   return !bin_name(id).isEmpty();
}

QString CLibraryStore::resolved_bin_id(const QString& bin_id) const {
   if (bin_id.isEmpty()) {
      return root_bin_id();
   }
   return bin_id;
}

std::vector<QString> CLibraryStore::bin_subtree_ids(
    const QString& root_id) const {
   std::vector<QString> ids;
   QSet<QString> seen;
   std::vector<QString> pending;
   pending.push_back(root_id);
   const std::vector<LibraryBin> all = bins();
   while (!pending.empty()) {
      const QString current = pending.back();
      pending.pop_back();
      if (seen.contains(current)) {
         continue;
      }
      seen.insert(current);
      ids.push_back(current);
      for (const LibraryBin& bin : all) {
         if (bin.parent_id == current) {
            pending.push_back(bin.id);
         }
      }
   }
   return ids;
}

bool CLibraryStore::is_in_bin_subtree(
    const QString& node, const QString& ancestor) const {
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
      current = bin_parent(current);
   }
   return false;
}

QString CLibraryStore::asset_id_by_fingerprint(
    const QString& fingerprint) const {
   if (fingerprint.isEmpty()) {
      return {};
   }
   for (const LibraryAsset& asset : assets()) {
      if (asset.fingerprint == fingerprint) {
         return asset.id;
      }
   }
   return {};
}

void CLibraryStore::set_last_error(const QString& error) {
   if (last_error_ == error) {
      return;
   }
   last_error_ = error;
   emit library_changed();
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
