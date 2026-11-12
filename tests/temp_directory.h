#pragma once

#include <QObject>
#include <QString>

/**
 * @brief Временный каталог и ключ library/path для проверок.
 */
class CTempDirectory : public QObject {
   Q_OBJECT

 public:
   /**
    * @brief Создаёт помощник проверки.
    * @param parent - владелец объекта.
    */
   explicit CTempDirectory(QObject* parent = nullptr);

   /**
    * @brief Создаёт пустой временный каталог.
    * @return путь каталога.
    */
   Q_INVOKABLE QString make();

   /**
    * @brief Удаляет каталог с содержимым.
    * @param path - каталог.
    */
   Q_INVOKABLE void remove_tree(const QString& path);

   /**
    * @brief Записывает library/path.
    * @param path - папка библиотеки.
    */
   Q_INVOKABLE void save_library_path(const QString& path);

   /**
    * @brief Удаляет ключ library/path.
    */
   Q_INVOKABLE void clear_library_path();
};
