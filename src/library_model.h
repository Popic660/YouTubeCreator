#pragma once

#include "library_store.h"

#include <QAbstractListModel>
#include <QSet>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <vector>

/**
 * @brief Плоский список видимых папок и роликов.
 */
class CLibraryModel : public QAbstractListModel {
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
    * @param parent - владелец объекта.
    */
   explicit CLibraryModel(QObject* parent = nullptr);

   /**
    * @brief Возвращает хранилище.
    * @return хранилище или nullptr.
    */
   CLibraryStore* store() const { return store_; }

   /**
    * @brief Подключает хранилище.
    * @param store - база библиотеки.
    */
   void set_store(CLibraryStore* store);

   /**
    * @brief Возвращает текст фильтра.
    * @return подстрока имени.
    */
   QString filter() const { return filter_; }

   /**
    * @brief Задаёт фильтр по имени.
    * @param filter - подстрока или пустая строка.
    */
   void set_filter(const QString& filter);

   /**
    * @brief Возвращает число видимых строк.
    * @return число строк.
    */
   int count() const;

   int rowCount(const QModelIndex& parent = QModelIndex())
       const override;
   QVariant data(const QModelIndex& index,
                 int role = Qt::DisplayRole) const override;
   QHash<int, QByteArray> roleNames() const override;

   /**
    * @brief Возвращает id строки.
    * @param row - индекс строки.
    * @return id или пустая строка.
    */
   Q_INVOKABLE QString row_id(int row) const;

   /**
    * @brief Возвращает вид строки.
    * @param row - индекс строки.
    * @return folder, short или пустая строка.
    */
   Q_INVOKABLE QString row_kind(int row) const;

   /**
    * @brief Возвращает имя строки.
    * @param row - индекс строки.
    * @return имя или пустая строка.
    */
   Q_INVOKABLE QString row_name(int row) const;

   /**
    * @brief Возвращает глубину строки.
    * @param row - индекс строки.
    * @return глубина от корня.
    */
   Q_INVOKABLE int row_depth(int row) const;

   /**
    * @brief Раскрывает или сворачивает папку в строке.
    * @param row - индекс строки.
    */
   Q_INVOKABLE void toggle_row(int row);

   /**
    * @brief Раскрывает или сворачивает папку по id.
    * @param id - id папки.
    */
   Q_INVOKABLE void toggle_id(const QString& id);

 signals:
   /**
    * @brief Сменилось хранилище.
    */
   void store_changed();

   /**
    * @brief Сменился фильтр.
    */
   void filter_changed();

   /**
    * @brief Сменилось число строк.
    */
   void count_changed();

 private:
   enum Role : int {
      kIdRole = Qt::UserRole + 1,
      kKindRole,
      kNameRole,
      kDepthRole,
      kExpandedRole,
      kHasChildrenRole,
   };

   struct Row {
      QString id;
      QString kind;
      QString name;
      int depth = 0;
      bool expanded = false;
      bool has_children = false;
   };

   void reload();
   void rebuild();
   const Row* row_at(int row) const;

   CLibraryStore* store_ = nullptr;
   QString filter_;
   std::vector<Row> rows_;
   QSet<QString> expanded_;
};
