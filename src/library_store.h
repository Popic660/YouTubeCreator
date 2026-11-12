#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <vector>

/**
 * @brief Папка библиотеки.
 */
struct LibraryFolder {
   QString id;
   QString parent_id;
   QString name;
   QString prompt;
};

/**
 * @brief Ролик-черновик библиотеки.
 */
struct LibraryShort {
   QString id;
   QString folder_id;
   QString name;
   QString status;
   qint64 duration_ms = 0;
   QString poster_relpath;
};

/**
 * @brief Папки и ролики в library.db выбранной папки.
 */
class CLibraryStore : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(bool opened READ is_opened NOTIFY open_changed)
   Q_PROPERTY(QString rootPath READ root_path NOTIFY open_changed)

 public:
   /**
    * @brief Создаёт закрытое хранилище.
    * @param parent - владелец объекта.
    */
   explicit CLibraryStore(QObject* parent = nullptr);

   ~CLibraryStore() override;

   /**
    * @brief Сообщает, открыта ли база.
    * @return true, если library.db открыт.
    */
   bool is_opened() const { return opened_; }

   /**
    * @brief Возвращает выбранную папку библиотеки.
    * @return путь или пустая строка.
    */
   QString root_path() const { return root_path_; }

   /**
    * @brief Открывает library.db в каталоге.
    * @param directory - папка библиотеки или file-URL.
    * @return true, если база открыта.
    */
   Q_INVOKABLE bool open(const QString& directory);

   /**
    * @brief Закрывает базу.
    */
   Q_INVOKABLE void close();

   /**
    * @brief Открывает папку из ключа library/path.
    * @return true, если база открыта.
    */
   Q_INVOKABLE bool open_saved();

   /**
    * @brief Записывает текущую папку в library/path.
    */
   Q_INVOKABLE void remember();

   /**
    * @brief Записывает путь библиотеки, не открывая её.
    * @param directory - папка библиотеки.
    */
   Q_INVOKABLE void save_path(const QString& directory);

   /**
    * @brief Удаляет ключ library/path.
    */
   Q_INVOKABLE void clear_saved_path();

   /**
    * @brief Возвращает user_version базы.
    * @return версия или -1, если база закрыта.
    */
   Q_INVOKABLE int user_version() const;

   /**
    * @brief Проверяет имя таблицы или индекса.
    * @param name - имя объекта sqlite_master.
    * @return true, если объект есть.
    */
   Q_INVOKABLE bool schema_contains(const QString& name) const;

   /**
    * @brief Создаёт папку.
    * @param parent_id - id родителя или пусто для корня.
    * @param name - имя папки.
    * @return id новой папки или пустая строка.
    */
   Q_INVOKABLE QString create_folder(const QString& parent_id,
                                     const QString& name);

   /**
    * @brief Возвращает имя папки.
    * @param id - id папки.
    * @return имя или пустая строка.
    */
   Q_INVOKABLE QString folder_name(const QString& id) const;

   /**
    * @brief Возвращает id родителя.
    * @param id - id папки.
    * @return id родителя или пустая строка для корня.
    */
   Q_INVOKABLE QString folder_parent(const QString& id) const;

   /**
    * @brief Переименовывает папку.
    * @param id - id папки.
    * @param name - новое имя.
    * @return true, если имя записано.
    */
   Q_INVOKABLE bool rename_folder(const QString& id, const QString& name);

   /**
    * @brief Возвращает собственный промпт папки.
    * @param id - id папки.
    * @return текст промпта.
    */
   Q_INVOKABLE QString folder_prompt(const QString& id) const;

   /**
    * @brief Записывает собственный промпт папки.
    * @param id - id папки.
    * @param prompt - собственный текст.
    * @return true, если запись обновлена.
    */
   Q_INVOKABLE bool set_folder_prompt(const QString& id,
                                      const QString& prompt);

   /**
    * @brief Собирает эффективный промпт от корня к папке.
    * @param id - id папки.
    * @return тексты через пустую строку.
    */
   Q_INVOKABLE QString effective_prompt(const QString& id) const;

   /**
    * @brief Сообщает, нужно ли подтверждение удаления папки.
    * @param id - id папки.
    * @return true, если в поддереве есть ролик.
    */
   Q_INVOKABLE bool folder_needs_confirmation(const QString& id) const;

   /**
    * @brief Удаляет папку и её поддерево.
    * @param id - id папки.
    * @param confirmed - true, если пользователь подтвердил.
    * @return true, если папка удалена.
    */
   Q_INVOKABLE bool delete_folder(const QString& id, bool confirmed);

   /**
    * @brief Создаёт ролик-черновик без файла.
    * @param folder_id - папка ролика.
    * @param name - имя ролика.
    * @return id ролика или пустая строка.
    */
   Q_INVOKABLE QString create_short(const QString& folder_id,
                                    const QString& name);

   /**
    * @brief Возвращает имя ролика.
    * @param id - id ролика.
    * @return имя или пустая строка.
    */
   Q_INVOKABLE QString short_name(const QString& id) const;

   /**
    * @brief Возвращает папку ролика.
    * @param id - id ролика.
    * @return id папки или пустая строка.
    */
   Q_INVOKABLE QString short_folder(const QString& id) const;

   /**
    * @brief Возвращает статус ролика.
    * @param id - id ролика.
    * @return статус или пустая строка.
    */
   Q_INVOKABLE QString short_status(const QString& id) const;

   /**
    * @brief Сообщает, есть ли постер.
    * @param id - id ролика.
    * @return true, если файл постера есть.
    */
   Q_INVOKABLE bool short_has_poster(const QString& id) const;

   /**
    * @brief Длительность ролика.
    * @param id - id ролика.
    * @return миллисекунды.
    */
   Q_INVOKABLE qint64 short_duration_ms(const QString& id) const;

   /**
    * @brief Абсолютный путь постера.
    * @param id - id ролика.
    * @return путь или пусто.
    */
   Q_INVOKABLE QString short_poster_path(const QString& id) const;

   /**
    * @brief Пишет длительность и постер карточки.
    * @param id - id ролика.
    * @param duration_ms - длительность.
    * @param poster_relpath - путь внутри библиотеки.
    * @return true, если строка обновлена.
    */
   Q_INVOKABLE bool update_short_media(const QString& id,
                                       qint64 duration_ms,
                                       const QString& poster_relpath);

   /**
    * @brief Импортирует видео в папку.
    * @param folder_id - папка.
    * @param path - файл.
    * @return id ролика или пусто.
    */
   Q_INVOKABLE QString import_video(const QString& folder_id,
                                    const QString& path);

   /**
    * @brief Импортирует видео в черновик.
    * @param short_id - ролик.
    * @param path - файл.
    * @return true, если клип записан.
    */
   Q_INVOKABLE bool import_into_short(const QString& short_id,
                                      const QString& path);

   /**
    * @brief Переименовывает ролик.
    * @param id - id ролика.
    * @param name - новое имя.
    * @return true, если имя записано.
    */
   Q_INVOKABLE bool rename_short(const QString& id, const QString& name);

   /**
    * @brief Сообщает, что удаление ролика требует подтверждения.
    * @param id - id ролика.
    * @return true, если ролик есть.
    */
   Q_INVOKABLE bool short_needs_confirmation(const QString& id) const;

   /**
    * @brief Удаляет ролик после подтверждения.
    * @param id - id ролика.
    * @param confirmed - true, если пользователь подтвердил.
    * @return true, если ролик удалён.
    */
   Q_INVOKABLE bool delete_short(const QString& id, bool confirmed);

   /**
    * @brief Переносит ролик в другую папку.
    * @param id - id ролика.
    * @param folder_id - новая папка.
    * @return true, если папка ролика изменена.
    */
   Q_INVOKABLE bool move_short(const QString& id, const QString& folder_id);

   /**
    * @brief Делает папку вложенной в другую.
    * @param id - переносимая папка.
    * @param parent_id - новая родительская папка или пусто.
    * @return true, если родитель изменён или уже такой.
    */
   Q_INVOKABLE bool reparent_folder(const QString& id,
                                    const QString& parent_id);

   /**
    * @brief Возвращает все папки.
    * @return записи folders.
    */
   std::vector<LibraryFolder> folders() const;

   /**
    * @brief Возвращает все ролики.
    * @return записи shorts.
    */
   std::vector<LibraryShort> shorts() const;

 signals:
   /**
    * @brief База открыта или закрыта.
    */
   void open_changed();

   /**
    * @brief Состав библиотеки изменился.
    */
   void library_changed();

 private:
   bool create_schema();
   bool migrate_from_v1();
   void remove_short_files(const QString& id);
   int read_user_version() const;
   void release_connection();
   bool folder_exists(const QString& id) const;
   std::vector<QString> subtree_ids(const QString& root_id) const;
   bool is_in_subtree(const QString& node,
                      const QString& ancestor) const;
   void notify_changed();

   bool opened_ = false;
   QString root_path_;
   QString connection_name_;
};
