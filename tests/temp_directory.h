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
    * @brief Создаёт library.db схемы 2 с роликом и клипом.
    * @param directory - папка библиотеки.
    * @return true, если файлы записаны.
    */
   Q_INVOKABLE bool seed_schema_v2(const QString& directory);

   /**
    * @brief Создаёт library.db схемы 3 с папкой и черновиком.
    * @param directory - папка библиотеки.
    * @return true, если файл записан.
    */
   Q_INVOKABLE bool seed_schema_v3(const QString& directory);

   /**
    * @brief Создаёт library.db схемы 4 с темой и сценарием.
    * @param directory - папка библиотеки.
    * @return true, если файл записан.
    */
   Q_INVOKABLE bool seed_schema_v4(const QString& directory);

   /**
    * @brief Создаёт library.db схемы 5 с обложкой.
    * @param directory - папка библиотеки.
    * @return true, если файл записан.
    */
   Q_INVOKABLE bool seed_schema_v5(const QString& directory);

   /**
    * @brief Создаёт library.db схемы 6 с каналом.
    * @param directory - папка библиотеки.
    * @return true, если файл записан.
    */
   Q_INVOKABLE bool seed_schema_v6(const QString& directory);

   /**
    * @brief Пишет PNG-картинку во временную папку.
    * @param directory - каталог.
    * @return путь файла.
    */
   Q_INVOKABLE QString make_image(const QString& directory) const;

   /**
    * @brief Пишет WAV-файл во временную папку.
    * @param directory - каталог.
    * @return путь файла.
    */
   Q_INVOKABLE QString make_wav(const QString& directory) const;

   /**
    * @brief Пишет текст в файл.
    * @param path - путь.
    * @param text - содержимое.
    * @return true, если записано.
    */
   Q_INVOKABLE bool write_text(const QString& path,
                               const QString& text) const;

   /**
    * @brief Создаёт каталог со родителями.
    * @param path - каталог.
    * @return true, если путь есть.
    */
   Q_INVOKABLE bool mkpath(const QString& path) const;

   /**
    * @brief Копирует файл.
    * @param source - исходник.
    * @param dest - назначение.
    * @return true, если копия есть.
    */
   Q_INVOKABLE bool copy_file(const QString& source,
                              const QString& dest) const;

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

   /**
    * @brief Ширина картинки.
    * @param path - путь.
    * @return пиксели.
    */
   Q_INVOKABLE int image_width(const QString& path) const;

   /**
    * @brief Высота картинки.
    * @param path - путь.
    * @return пиксели.
    */
   Q_INVOKABLE int image_height(const QString& path) const;
};
