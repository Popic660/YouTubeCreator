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
   QString topic;
   QString script;
};

/**
 * @brief Бин пула ассетов.
 */
struct LibraryBin {
   QString id;
   QString parent_id;
   QString name;
};

/**
 * @brief Ассет пула.
 */
struct LibraryAsset {
   QString id;
   QString bin_id;
   QString name;
   QString kind;
   QString relpath;
   qint64 duration_ms = 0;
   qint64 in_ms = 0;
   qint64 out_ms = 0;
   QString fingerprint;
   qint64 size = 0;
};

/**
 * @brief Папки и ролики в library.db выбранной папки.
 */
class CLibraryStore : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(bool opened READ is_opened NOTIFY open_changed)
   Q_PROPERTY(QString rootPath READ root_path NOTIFY open_changed)
   Q_PROPERTY(QString rootBinId READ root_bin_id NOTIFY open_changed)
   Q_PROPERTY(QString lastError READ last_error NOTIFY library_changed)

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
    * @brief Возвращает тему ролика.
    * @param id - id ролика.
    * @return тема или пусто.
    */
   Q_INVOKABLE QString short_topic(const QString& id) const;

   /**
    * @brief Пишет тему ролика.
    * @param id - id ролика.
    * @param topic - текст темы.
    * @return true, если записано.
    */
   Q_INVOKABLE bool set_topic(const QString& id, const QString& topic);

   /**
    * @brief Возвращает сценарий ролика.
    * @param id - id ролика.
    * @return сценарий или пусто.
    */
   Q_INVOKABLE QString short_script(const QString& id) const;

   /**
    * @brief Пишет сценарий ролика.
    * @param id - id ролика.
    * @param script - текст сценария.
    * @return true, если записано.
    */
   Q_INVOKABLE bool set_script(const QString& id,
                               const QString& script);

   /**
    * @brief Пишет статус ролика.
    * @param id - id ролика.
    * @param status - draft или generating.
    * @return true, если записано.
    */
   Q_INVOKABLE bool set_short_status(const QString& id,
                                     const QString& status);

   /**
    * @brief Создаёт задачу конвейера.
    * @param short_id - ролик.
    * @param step - text или voice.
    * @return id задачи или пусто.
    */
   Q_INVOKABLE QString start_task(const QString& short_id,
                                  const QString& step);

   /**
    * @brief Обновляет задачу.
    * @param id - задача.
    * @param step - шаг.
    * @param status - running, done, error, cancelled, interrupted.
    * @param progress - 0..100.
    * @param error - текст ошибки.
    * @return true, если записано.
    */
   Q_INVOKABLE bool update_task(const QString& id, const QString& step,
                                const QString& status, int progress,
                                const QString& error);

   /**
    * @brief Статус последней задачи ролика.
    * @param short_id - ролик.
    * @return статус или пусто.
    */
   Q_INVOKABLE QString task_status(const QString& short_id) const;

   /**
    * @brief Шаг последней задачи ролика.
    * @param short_id - ролик.
    * @return шаг или пусто.
    */
   Q_INVOKABLE QString task_step(const QString& short_id) const;

   /**
    * @brief Прогресс последней задачи ролика.
    * @param short_id - ролик.
    * @return 0..100.
    */
   Q_INVOKABLE int task_progress(const QString& short_id) const;

   /**
    * @brief Ошибка последней задачи ролика.
    * @param short_id - ролик.
    * @return текст или пусто.
    */
   Q_INVOKABLE QString task_error(const QString& short_id) const;

   /**
    * @brief Пишет задачу для проверки прерывания.
    * @param short_id - ролик.
    * @param step - шаг.
    * @param status - статус.
    * @return id задачи или пусто.
    */
   Q_INVOKABLE QString insert_task(const QString& short_id,
                                   const QString& step,
                                   const QString& status);

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
   /**
    * @brief Импортирует файл в бин пула.
    * @param bin_id - бин или пусто для корня.
    * @param path - файл.
    * @return id ассета или пусто.
    */
   Q_INVOKABLE QString import_media(const QString& bin_id,
                                    const QString& path);

   /**
    * @brief Импортирует папку как бины и ассеты.
    * @param bin_id - родительский бин или пусто для корня.
    * @param path - папка на диске.
    * @return id созданного бина или пусто.
    */
   Q_INVOKABLE QString import_folder(const QString& bin_id,
                                     const QString& path);

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

   /**
    * @brief Возвращает id корневого бина.
    * @return id или пусто.
    */
   Q_INVOKABLE QString root_bin_id() const;

   /**
    * @brief Последняя ошибка пула.
    * @return busy или пусто.
    */
   QString last_error() const { return last_error_; }

   /**
    * @brief Создаёт бин.
    * @param parent_id - родитель или пусто для корня.
    * @param name - имя.
    * @return id или пусто.
    */
   Q_INVOKABLE QString create_bin(const QString& parent_id,
                                  const QString& name);

   /**
    * @brief Имя бина.
    * @param id - бин.
    * @return имя или пусто.
    */
   Q_INVOKABLE QString bin_name(const QString& id) const;

   /**
    * @brief Родитель бина.
    * @param id - бин.
    * @return id родителя или пусто.
    */
   Q_INVOKABLE QString bin_parent(const QString& id) const;

   /**
    * @brief Переименовывает бин.
    * @param id - бин.
    * @param name - новое имя.
    * @return true, если записано.
    */
   Q_INVOKABLE bool rename_bin(const QString& id, const QString& name);

   /**
    * @brief Переносит бин.
    * @param id - бин.
    * @param parent_id - новый родитель или корень.
    * @return true, если родитель изменён или уже такой.
    */
   Q_INVOKABLE bool reparent_bin(const QString& id,
                                 const QString& parent_id);

   /**
    * @brief Удаляет пустой бин.
    * @param id - бин.
    * @return true, если удалён.
    */
   Q_INVOKABLE bool delete_bin(const QString& id);

   /**
    * @brief Имя ассета.
    * @param id - ассет.
    * @return имя или пусто.
    */
   Q_INVOKABLE QString asset_name(const QString& id) const;

   /**
    * @brief Тип ассета.
    * @param id - ассет.
    * @return video, audio, image или пусто.
    */
   Q_INVOKABLE QString asset_kind(const QString& id) const;

   /**
    * @brief Бин ассета.
    * @param id - ассет.
    * @return id бина.
    */
   Q_INVOKABLE QString asset_bin(const QString& id) const;

   /**
    * @brief Относительный путь копии.
    * @param id - ассет.
    * @return путь внутри библиотеки.
    */
   Q_INVOKABLE QString asset_relpath(const QString& id) const;

   /**
    * @brief Абсолютный путь копии ассета.
    * @param id - ассет.
    * @return путь или пусто.
    */
   Q_INVOKABLE QString asset_abs_path(const QString& id) const;

   /**
    * @brief Длительность ассета.
    * @param id - ассет.
    * @return миллисекунды.
    */
   Q_INVOKABLE qint64 asset_duration_ms(const QString& id) const;

   /**
    * @brief Вход ассета.
    * @param id - ассет.
    * @return миллисекунды.
    */
   Q_INVOKABLE qint64 asset_in_ms(const QString& id) const;

   /**
    * @brief Выход ассета.
    * @param id - ассет.
    * @return миллисекунды.
    */
   Q_INVOKABLE qint64 asset_out_ms(const QString& id) const;

   /**
    * @brief Задаёт вход и выход ассета.
    * @param id - ассет.
    * @param in_ms - вход.
    * @param out_ms - выход.
    * @return true, если записано.
    */
   Q_INVOKABLE bool set_asset_marks(const QString& id, qint64 in_ms,
                                    qint64 out_ms);

   /**
    * @brief Переносит ассет в другой бин.
    * @param id - ассет.
    * @param bin_id - бин.
    * @return true, если бин изменён.
    */
   Q_INVOKABLE bool move_asset(const QString& id, const QString& bin_id);

   /**
    * @brief Удаляет ассет после подтверждения.
    * @param id - ассет.
    * @param confirmed - подтверждение.
    * @return true, если удалён.
    */
   Q_INVOKABLE bool delete_asset(const QString& id, bool confirmed);

   /**
    * @brief Сообщает, что ассет стоит на таймлайне.
    * @param id - ассет.
    * @return true, если есть клип с этим asset_id.
    */
   Q_INVOKABLE bool asset_is_busy(const QString& id) const;

   /**
    * @brief Число ассетов.
    * @return строки assets.
    */
   Q_INVOKABLE int asset_count() const;

   /**
    * @brief Число файлов в media/.
    * @return файлы, не каталоги.
    */
   Q_INVOKABLE int media_file_count() const;

   /**
    * @brief Число роликов.
    * @return строки shorts.
    */
   Q_INVOKABLE int short_count() const;

   /**
    * @brief Число бинов.
    * @return строки bins.
    */
   Q_INVOKABLE int bin_count() const;

   /**
    * @brief Все бины.
    * @return записи bins.
    */
   std::vector<LibraryBin> bins() const;

   /**
    * @brief Все ассеты.
    * @return записи assets.
    */
   std::vector<LibraryAsset> assets() const;

   /**
    * @brief Ассет по id.
    * @param id - ассет.
    * @return запись или пустой id.
    */
   LibraryAsset asset_by_id(const QString& id) const;

   /**
    * @brief Ищет бин по имени.
    * @param name - имя.
    * @return id или пусто.
    */
   Q_INVOKABLE QString bin_by_name(const QString& name) const;

   /**
    * @brief Ищет ассет по имени.
    * @param name - имя.
    * @return id или пусто.
    */
   Q_INVOKABLE QString asset_by_name(const QString& name) const;

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
   bool migrate_from_v2();
   bool migrate_from_v3();
   bool interrupt_running_tasks();
   QString latest_task_field(const QString& short_id,
                             const QString& field) const;
   bool ensure_pool_tables();
   bool ensure_root_bin();
   bool register_assets_from_projects();
   void remove_short_files(const QString& id);
   int read_user_version() const;
   void release_connection();
   bool folder_exists(const QString& id) const;
   bool bin_exists(const QString& id) const;
   QString resolved_bin_id(const QString& bin_id) const;
   std::vector<QString> subtree_ids(const QString& root_id) const;
   std::vector<QString> bin_subtree_ids(const QString& root_id) const;
   bool is_in_subtree(const QString& node,
                      const QString& ancestor) const;
   bool is_in_bin_subtree(const QString& node,
                          const QString& ancestor) const;
   QString asset_id_by_fingerprint(const QString& fingerprint) const;
   void set_last_error(const QString& error);
   void notify_changed();

   bool opened_ = false;
   QString root_path_;
   QString connection_name_;
   QString last_error_;
};
