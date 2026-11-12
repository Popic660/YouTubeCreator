#pragma once

#include "library_store.h"

#include <QAbstractListModel>
#include <QSet>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <vector>

/**
 * @brief Плоский список видимых бинов и ассетов.
 */
class CMediaModel : public QAbstractListModel {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(CLibraryStore* store READ store WRITE set_store
                  NOTIFY store_changed)
   Q_PROPERTY(QString filter READ filter WRITE set_filter
                  NOTIFY filter_changed)
   Q_PROPERTY(int count READ count NOTIFY count_changed)

 public:
   /**
    * @brief Создаёт пустую модель.
    * @param parent - владелец.
    */
   explicit CMediaModel(QObject* parent = nullptr);

   CLibraryStore* store() const { return store_; }
   /**
    * @brief Подключает хранилище.
    * @param store - база библиотеки.
    */
   void set_store(CLibraryStore* store);

   QString filter() const { return filter_; }
   /**
    * @brief Задаёт фильтр по имени.
    * @param filter - подстрока.
    */
   void set_filter(const QString& filter);

   int count() const;
   int rowCount(const QModelIndex& parent = QModelIndex())
       const override;
   QVariant data(const QModelIndex& index,
                 int role = Qt::DisplayRole) const override;
   QHash<int, QByteArray> roleNames() const override;

   Q_INVOKABLE QString row_id(int row) const;
   Q_INVOKABLE QString row_kind(int row) const;
   Q_INVOKABLE QString row_name(int row) const;
   Q_INVOKABLE int row_depth(int row) const;
   Q_INVOKABLE void toggle_row(int row);
   Q_INVOKABLE void toggle_id(const QString& id);

 signals:
   void store_changed();
   void filter_changed();
   void count_changed();

 private:
   enum Role : int {
      kIdRole = Qt::UserRole + 1,
      kKindRole,
      kNameRole,
      kDepthRole,
      kExpandedRole,
      kHasChildrenRole,
      kDurationRole,
      kGlyphRole,
   };

   struct Row {
      QString id;
      QString kind;
      QString name;
      int depth = 0;
      bool expanded = false;
      bool has_children = false;
      qint64 duration_ms = 0;
      QString glyph;
   };

   void reload();
   void rebuild();
   const Row* row_at(int row) const;

   CLibraryStore* store_ = nullptr;
   QString filter_;
   std::vector<Row> rows_;
   QSet<QString> expanded_;
};
