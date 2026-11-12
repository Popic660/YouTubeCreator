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

   /**
    * @brief Создаёт library.db схемы 1.
    * @param directory - папка библиотеки.
    * @return true, если файл записан.
    */
   Q_INVOKABLE bool seed_schema_v1(const QString& directory);

   /**
    * @brief Путь к фикстуре теста.
    * @param name - имя файла в fixtures/.
    * @return абсолютный путь.
    */
   Q_INVOKABLE QString fixture_path(const QString& name) const;

   /**
    * @brief Проверяет файл.
    * @param path - путь.
    * @return true, если файл есть.
    */
   Q_INVOKABLE bool file_exists(const QString& path) const;

   /**
    * @brief Читает текст файла.
    * @param path - путь.
    * @return содержимое или пусто.
    */
   Q_INVOKABLE QString read_text(const QString& path) const;

   /**
    * @brief Ширина видеофайла.
    * @param path - путь.
    * @return пиксели.
    */
   Q_INVOKABLE int video_width(const QString& path) const;

   /**
    * @brief Высота видеофайла.
    * @param path - путь.
    * @return пиксели.
    */
   Q_INVOKABLE int video_height(const QString& path) const;
};
