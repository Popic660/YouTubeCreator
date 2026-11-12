#include "media_model.h"

#include <algorithm>
#include <ranges>

namespace {

struct ChildRef {
   QString id;
   QString kind;
   QString name;
};

bool name_less(const ChildRef& left, const ChildRef& right) {
   const int compared = QString::compare(
       left.name, right.name, Qt::CaseInsensitive);
   if (compared != 0) {
      return compared < 0;
   }
   return left.id < right.id;
}

QString glyph_for_kind(const QString& kind) {
   if (kind == QLatin1String("audio")) {
      return QStringLiteral("audio");
   }
   if (kind == QLatin1String("image")) {
      return QStringLiteral("image");
   }
   if (kind == QLatin1String("bin")) {
      return QStringLiteral("bin");
   }
   return QStringLiteral("film");
}

}  // namespace

CMediaModel::CMediaModel(QObject* parent)
    : QAbstractListModel(parent) {}

void CMediaModel::set_store(CLibraryStore* store) {
   if (store_ == store) {
      return;
   }
   if (store_ != nullptr) {
      disconnect(store_, nullptr, this, nullptr);
   }
   store_ = store;
   if (store_ != nullptr) {
      connect(store_, &CLibraryStore::library_changed, this,
              &CMediaModel::reload);
      connect(store_, &CLibraryStore::open_changed, this,
              &CMediaModel::reload);
   }
   reload();
   emit store_changed();
}

void CMediaModel::set_filter(const QString& filter) {
   if (filter_ == filter) {
      return;
   }
   filter_ = filter;
   reload();
   emit filter_changed();
}

int CMediaModel::count() const {
   return static_cast<int>(rows_.size());
}

int CMediaModel::rowCount(const QModelIndex& parent) const {
   if (parent.isValid()) {
      return 0;
   }
   return count();
}

QVariant CMediaModel::data(const QModelIndex& index,
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
      case kGlyphRole:
         return row->glyph;
      default:
         return {};
   }
}

QHash<int, QByteArray> CMediaModel::roleNames() const {
   return {
       {kIdRole, "entryId"},
       {kKindRole, "kind"},
       {kNameRole, "name"},
       {kDepthRole, "depth"},
       {kExpandedRole, "expanded"},
       {kHasChildrenRole, "hasChildren"},
       {kDurationRole, "durationMs"},
       {kGlyphRole, "glyphName"},
   };
}

QString CMediaModel::row_id(int row) const {
   const Row* item = row_at(row);
   return item == nullptr ? QString() : item->id;
}

QString CMediaModel::row_kind(int row) const {
   const Row* item = row_at(row);
   return item == nullptr ? QString() : item->kind;
}

QString CMediaModel::row_name(int row) const {
   const Row* item = row_at(row);
   return item == nullptr ? QString() : item->name;
}

int CMediaModel::row_depth(int row) const {
   const Row* item = row_at(row);
   return item == nullptr ? 0 : item->depth;
}

void CMediaModel::toggle_row(int row) {
   const Row* item = row_at(row);
   if (item == nullptr || item->kind != "bin") {
      return;
   }
   toggle_id(item->id);
}

void CMediaModel::toggle_id(const QString& id) {
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

void CMediaModel::reload() {
   beginResetModel();
   rows_.clear();
   if (store_ != nullptr && store_->is_opened()) {
      rebuild();
   }
   endResetModel();
   emit count_changed();
}

const CMediaModel::Row* CMediaModel::row_at(int row) const {
   if (row < 0 || row >= count()) {
      return nullptr;
   }
   return &rows_[static_cast<std::size_t>(row)];
}

void CMediaModel::rebuild() {
   const std::vector<LibraryBin> bins = store_->bins();
   const std::vector<LibraryAsset> assets = store_->assets();
   const QString root = store_->root_bin_id();
   const bool filtering = !filter_.isEmpty();
   const auto matches = [this](const QString& name) {
      return name.contains(filter_, Qt::CaseInsensitive);
   };

   const auto children_of = [&](const QString& bin_id) {
      std::vector<ChildRef> children;
      for (const LibraryBin& bin : bins) {
         if (bin.parent_id == bin_id && bin.id != root) {
            children.push_back({bin.id, "bin", bin.name});
         }
      }
      for (const LibraryAsset& asset : assets) {
         if (asset.bin_id == bin_id) {
            children.push_back({asset.id, asset.kind, asset.name});
         }
      }
      std::ranges::sort(children, name_less);
      return children;
   };

   QSet<QString> kept;
   const auto bin_kept = [&](const QString& bin_id,
                             auto&& self) -> bool {
      if (kept.contains(bin_id)) {
         return true;
      }
      const LibraryBin* found = nullptr;
      for (const LibraryBin& bin : bins) {
         if (bin.id == bin_id) {
            found = &bin;
            break;
         }
      }
      if (found == nullptr) {
         return false;
      }
      if (bin_id != root && matches(found->name)) {
         kept.insert(bin_id);
         return true;
      }
      for (const ChildRef& child : children_of(bin_id)) {
         if (child.kind != "bin" && matches(child.name)) {
            kept.insert(bin_id);
            return true;
         }
         if (child.kind == "bin" && self(child.id, self)) {
            kept.insert(bin_id);
            return true;
         }
      }
      return false;
   };

   const auto append_bin = [&](const QString& bin_id, int depth,
                               auto&& self) -> void {
      if (filtering && !bin_kept(bin_id, bin_kept)) {
         return;
      }
      const std::vector<ChildRef> children = children_of(bin_id);
      bool show_children = filtering || expanded_.contains(bin_id) ||
                           bin_id == root;
      if (bin_id != root) {
         QString name;
         for (const LibraryBin& bin : bins) {
            if (bin.id == bin_id) {
               name = bin.name;
               break;
            }
         }
         Row row;
         row.id = bin_id;
         row.kind = QStringLiteral("bin");
         row.name = name;
         row.depth = depth;
         row.expanded = show_children;
         row.has_children = !children.empty();
         row.glyph = QStringLiteral("bin");
         rows_.push_back(row);
      }
      if (!show_children) {
         return;
      }
      const int child_depth = bin_id == root ? 0 : depth + 1;
      for (const ChildRef& child : children) {
         if (child.kind == "bin") {
            self(child.id, child_depth, self);
            continue;
         }
         if (filtering && !matches(child.name)) {
            continue;
         }
         Row asset_row;
         asset_row.id = child.id;
         asset_row.kind = child.kind;
         asset_row.name = child.name;
         asset_row.depth = child_depth;
         asset_row.glyph = glyph_for_kind(child.kind);
         for (const LibraryAsset& asset : assets) {
            if (asset.id == child.id) {
               asset_row.duration_ms = asset.duration_ms;
               break;
            }
         }
         rows_.push_back(asset_row);
      }
   };

   if (!root.isEmpty()) {
      expanded_.insert(root);
      append_bin(root, 0, append_bin);
   }
}
