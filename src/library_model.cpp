#include "library_model.h"

#include "library_store.h"

#include <QSet>

#include <algorithm>
#include <ranges>

namespace {

struct ChildRef {
   QString id;
   QString kind;
   QString name;
};

/**
 * @brief Сравнивает имена без учёта регистра, затем id.
 * @param left - левая запись.
 * @param right - правая запись.
 * @return true, если left идёт раньше.
 */
bool name_less(const ChildRef& left, const ChildRef& right) {
   const int compared = QString::compare(
       left.name, right.name, Qt::CaseInsensitive);
   if (compared != 0) {
      return compared < 0;
   }
   return left.id < right.id;
}

}  // namespace

CLibraryModel::CLibraryModel(QObject* parent)
    : QAbstractListModel(parent) {}

void CLibraryModel::set_store(CLibraryStore* store) {
   if (store_ == store) {
      return;
   }
   if (store_ != nullptr) {
      disconnect(store_, nullptr, this, nullptr);
   }
   store_ = store;
   if (store_ != nullptr) {
      connect(store_, &CLibraryStore::library_changed, this,
              &CLibraryModel::reload);
      connect(store_, &CLibraryStore::open_changed, this,
              &CLibraryModel::reload);
   }
   reload();
   emit store_changed();
}

void CLibraryModel::set_filter(const QString& filter) {
   if (filter_ == filter) {
      return;
   }
   filter_ = filter;
   reload();
   emit filter_changed();
}

int CLibraryModel::count() const {
   return static_cast<int>(rows_.size());
}

int CLibraryModel::rowCount(const QModelIndex& parent) const {
   if (parent.isValid()) {
      return 0;
   }
   return count();
}

QVariant CLibraryModel::data(const QModelIndex& index,
                             int role) const {
   const Row* row = row_at(index.row());
   if (row == nullptr || index.column() != 0) {
      return {};
   }
   switch (role) {
      case Qt::DisplayRole:
      case kNameRole:
         return row->name;
      case kIdRole:
         return row->id;
      case kKindRole:
         return row->kind;
      case kDepthRole:
         return row->depth;
      case kExpandedRole:
         return row->expanded;
      case kHasChildrenRole:
         return row->has_children;
      case kDurationRole:
         return row->duration_ms;
      case kPosterRole:
         return row->poster_path;
      case kHasPosterRole:
         return row->has_poster;
      default:
         return {};
   }
}

QHash<int, QByteArray> CLibraryModel::roleNames() const {
   return {
       {kIdRole, "entryId"},
       {kKindRole, "kind"},
       {kNameRole, "name"},
       {kDepthRole, "depth"},
       {kExpandedRole, "expanded"},
       {kHasChildrenRole, "hasChildren"},
       {kDurationRole, "durationMs"},
       {kPosterRole, "posterPath"},
       {kHasPosterRole, "hasPoster"},
   };
}

QString CLibraryModel::row_id(int row) const {
   const Row* item = row_at(row);
   if (item == nullptr) {
      return {};
   }
   return item->id;
}

QString CLibraryModel::row_kind(int row) const {
   const Row* item = row_at(row);
   if (item == nullptr) {
      return {};
   }
   return item->kind;
}

QString CLibraryModel::row_name(int row) const {
   const Row* item = row_at(row);
   if (item == nullptr) {
      return {};
   }
   return item->name;
}

int CLibraryModel::row_depth(int row) const {
   const Row* item = row_at(row);
   if (item == nullptr) {
      return 0;
   }
   return item->depth;
}

void CLibraryModel::toggle_row(int row) {
   const Row* item = row_at(row);
   if (item == nullptr || item->kind != "folder") {
      return;
   }
   toggle_id(item->id);
}

void CLibraryModel::toggle_id(const QString& id) {
   if (id.isEmpty()) {
      return;
   }
   if (expanded_.contains(id)) {
      expanded_.remove(id);
   } else {
      expanded_.insert(id);
   }
   reload();
}

void CLibraryModel::reload() {
   beginResetModel();
   rows_.clear();
   if (store_ != nullptr && store_->is_opened()) {
      rebuild();
   }
   endResetModel();
   emit count_changed();
}

const CLibraryModel::Row* CLibraryModel::row_at(int row) const {
   if (row < 0 || row >= count()) {
      return nullptr;
   }
   return &rows_[static_cast<std::size_t>(row)];
}

void CLibraryModel::rebuild() {
   const std::vector<LibraryFolder> folders = store_->folders();
   const std::vector<LibraryShort> clips = store_->shorts();
   const bool filtering = !filter_.isEmpty();

   const auto matches = [this](const QString& name) {
      return name.contains(filter_, Qt::CaseInsensitive);
   };

   const auto children_of = [&](const QString& folder_id) {
      std::vector<ChildRef> children;
      for (const LibraryFolder& folder : folders) {
         if (folder.parent_id == folder_id) {
            children.push_back({folder.id, "folder", folder.name});
         }
      }
      for (const LibraryShort& clip : clips) {
         if (clip.folder_id == folder_id) {
            children.push_back({clip.id, "short", clip.name});
         }
      }
      std::ranges::sort(children, name_less);
      return children;
   };

   const auto has_any_child = [&](const QString& folder_id) {
      return !children_of(folder_id).empty();
   };

   QSet<QString> kept_folders;
   const auto folder_kept = [&](const QString& folder_id,
                                auto&& self) -> bool {
      if (kept_folders.contains(folder_id)) {
         return true;
      }
      const LibraryFolder* self_folder = nullptr;
      for (const LibraryFolder& folder : folders) {
         if (folder.id == folder_id) {
            self_folder = &folder;
            break;
         }
      }
      if (self_folder == nullptr) {
         return false;
      }
      if (matches(self_folder->name)) {
         kept_folders.insert(folder_id);
         return true;
      }
      for (const ChildRef& child : children_of(folder_id)) {
         if (child.kind == "short" && matches(child.name)) {
            kept_folders.insert(folder_id);
            return true;
         }
         if (child.kind == "folder" && self(child.id, self)) {
            kept_folders.insert(folder_id);
            return true;
         }
      }
      return false;
   };

   const auto append_folder = [&](const LibraryFolder& folder,
                                  int depth,
                                  auto&& self) -> void {
      if (filtering && !folder_kept(folder.id, folder_kept)) {
         return;
      }
      const std::vector<ChildRef> children = children_of(folder.id);
      bool show_children = false;
      if (filtering) {
         for (const ChildRef& child : children) {
            if (child.kind == "short" && matches(child.name)) {
               show_children = true;
               break;
            }
            if (child.kind == "folder" &&
                folder_kept(child.id, folder_kept)) {
               show_children = true;
               break;
            }
         }
      } else {
         show_children = expanded_.contains(folder.id);
      }

      Row row;
      row.id = folder.id;
      row.kind = "folder";
      row.name = folder.name;
      row.depth = depth;
      row.expanded = show_children;
      row.has_children = has_any_child(folder.id);
      rows_.push_back(row);
      if (!show_children) {
         return;
      }
      for (const ChildRef& child : children) {
         if (child.kind == "folder") {
            for (const LibraryFolder& nested : folders) {
               if (nested.id == child.id) {
                  self(nested, depth + 1, self);
                  break;
               }
            }
            continue;
         }
         if (filtering && !matches(child.name)) {
            continue;
         }
         Row clip_row;
         clip_row.id = child.id;
         clip_row.kind = "short";
         clip_row.name = child.name;
         clip_row.depth = depth + 1;
         for (const LibraryShort& clip : clips) {
            if (clip.id == child.id) {
               clip_row.duration_ms = clip.duration_ms;
               clip_row.poster_path =
                   store_->short_poster_path(clip.id);
               clip_row.has_poster = !clip_row.poster_path.isEmpty();
               break;
            }
         }
         rows_.push_back(clip_row);
      }
   };

   std::vector<LibraryFolder> roots;
   for (const LibraryFolder& folder : folders) {
      if (folder.parent_id.isEmpty()) {
         roots.push_back(folder);
      }
   }
   std::ranges::sort(roots, [](const LibraryFolder& left,
                               const LibraryFolder& right) {
      return name_less({left.id, "folder", left.name},
                       {right.id, "folder", right.name});
   });
   for (const LibraryFolder& root : roots) {
      append_folder(root, 0, append_folder);
   }
}
