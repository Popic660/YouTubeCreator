#pragma once

#include "library_store.h"

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

#include <vector>

/**
 * @brief Клип таймлайна.
 */
struct TimelineClip {
   QString id;
   QString track;
   QString kind;
   QString asset_id;
   QString file;
   qint64 in_ms = 0;
   qint64 out_ms = 0;
   qint64 start_ms = 0;
   double scale = 1.0;
   double offset_x = 0;
   double offset_y = 0;
   double volume = 1.0;
   QString text;
};

/**
 * @brief Проект ролика: клипы, ползунок, отмена и json.
 */
class CProjectDocument : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(CLibraryStore* store READ store WRITE set_store
                  NOTIFY store_changed)
   Q_PROPERTY(QString shortId READ short_id NOTIFY short_changed)
   Q_PROPERTY(bool hasClips READ has_clips NOTIFY timeline_changed)
   Q_PROPERTY(int clipCount READ clip_count NOTIFY timeline_changed)
   Q_PROPERTY(int audioCount READ audio_count NOTIFY timeline_changed)
   Q_PROPERTY(int textCount READ text_count NOTIFY timeline_changed)
   Q_PROPERTY(int itemCount READ item_count NOTIFY timeline_changed)
   Q_PROPERTY(qint64 playheadMs READ playhead_ms WRITE set_playhead_ms
                  NOTIFY playhead_changed)
   Q_PROPERTY(qint64 durationMs READ duration_ms NOTIFY timeline_changed)
   Q_PROPERTY(bool playing READ is_playing NOTIFY playing_changed)
   Q_PROPERTY(QString selectedClipId READ selected_clip_id
                  WRITE set_selected_clip_id
                  NOTIFY selection_changed)
   Q_PROPERTY(bool hasRecovery READ has_recovery
                  NOTIFY recovery_changed)

 public:
   /**
    * @brief Создаёт пустой документ.
    * @param parent - владелец.
    */
   explicit CProjectDocument(QObject* parent = nullptr);

   CLibraryStore* store() const { return store_; }
   /**
    * @brief Подключает библиотеку.
    * @param store - хранилище.
    */
   void set_store(CLibraryStore* store);

   QString short_id() const { return short_id_; }
   bool has_clips() const { return clip_count() > 0; }
   int clip_count() const;
   int audio_count() const;
   int text_count() const;
   int item_count() const;
   qint64 playhead_ms() const { return playhead_ms_; }
   bool is_playing() const { return playing_; }
   QString selected_clip_id() const { return selected_clip_id_; }

   /**
    * @brief Задаёт ползунок.
    * @param time_ms - время таймлайна.
    */
   void set_playhead_ms(qint64 time_ms);

   /**
    * @brief Выбирает клип.
    * @param id - id клипа.
    */
   void set_selected_clip_id(const QString& id);

   /**
    * @brief Открывает проект ролика.
    * @param short_id - id ролика.
    * @return true, если ролик есть.
    */
   Q_INVOKABLE bool open_short(const QString& short_id,
                               const QString& recovery = QString());

   /**
    * @brief Закрывает проект.
    */
   Q_INVOKABLE void close();

   /**
    * @brief Импортирует видео в папку.
    * @param folder_id - папка.
    * @param path - файл.
    * @return id ролика или пусто.
    */
   /**
    * @brief Импортирует файл в пул.
    * @param bin_id - бин или пусто для корня.
    * @param path - файл.
    * @return id ассета или пусто.
    */
   Q_INVOKABLE QString import_media(const QString& bin_id,
                                    const QString& path);

   Q_INVOKABLE QString import_video(const QString& folder_id,
                                    const QString& path);

   /**
    * @brief Кладёт ассет на дорожку.
    * @param asset_id - ассет пула.
    * @param track - v1, v2, a1 или пусто.
    * @param start_ms - старт на таймлайне.
    * @param insert - вставка со сдвигом хвоста.
    * @return id клипа или пусто.
    */
   Q_INVOKABLE QString place_asset(const QString& asset_id,
                                   const QString& track,
                                   qint64 start_ms, bool insert);

   /**
    * @brief Закрывает первый разрыв на дорожке выбора.
    * @return true, если клип сдвинут.
    */
   Q_INVOKABLE bool close_gap();

   /**
    * @brief Примагничивает время к краям и ползунку.
    * @param time_ms - исходное время.
    * @param ms_per_pixel - масштаб.
    * @return время после магнита.
    */
   Q_INVOKABLE qint64 snap_ms(qint64 time_ms,
                              double ms_per_pixel) const;

   /**
    * @brief Двигает клип по дорожке.
    * @param clip_id - клип.
    * @param start_ms - новый старт.
    * @return true, если записано.
    */
   Q_INVOKABLE bool move_clip(const QString& clip_id,
                              qint64 start_ms);

   /**
    * @brief Пишет recovery сразу.
    */
   Q_INVOKABLE void flush_recovery();

   /**
    * @brief Есть ли журнал ролика.
    * @return true, если recovery.json на диске.
    */
   bool has_recovery() const;

   /**
    * @brief Id ассета клипа.
    * @param clip_id - клип.
    * @return id или пусто.
    */
   Q_INVOKABLE QString clip_asset_id(const QString& clip_id) const;

   /**
    * @brief Импортирует видео в черновик.
    * @param short_id - ролик.
    * @param path - файл.
    * @return true, если клип записан.
    */
   Q_INVOKABLE bool import_into_short(const QString& short_id,
                                      const QString& path);

   /**
    * @brief Добавляет аудиоклип.
    * @param path - файл.
    * @return id клипа или пусто.
    */
   Q_INVOKABLE QString add_audio(const QString& path);

   /**
    * @brief Добавляет текст на V2.
    * @param text - надпись.
    * @return id клипа или пусто.
    */
   Q_INVOKABLE QString add_text(const QString& text);

   /**
    * @brief Режет клип в позиции ползунка.
    * @return true, если клип разделён.
    */
   Q_INVOKABLE bool split_at_playhead();

   /**
    * @brief Задаёт вход и выход клипа.
    * @param clip_id - клип.
    * @param in_ms - вход.
    * @param out_ms - выход.
    * @return true, если края записаны.
    */
   Q_INVOKABLE bool trim_clip(const QString& clip_id, qint64 in_ms,
                              qint64 out_ms);

   /**
    * @brief Задаёт громкость.
    * @param clip_id - клип.
    * @param volume - коэффициент.
    * @return true, если значение записано.
    */
   Q_INVOKABLE bool set_volume(const QString& clip_id, double volume);

   /**
    * @brief Задаёт масштаб и сдвиг.
    * @param clip_id - клип.
    * @param scale - множитель после cover.
    * @param offset_x - сдвиг по X.
    * @param offset_y - сдвиг по Y.
    * @return true, если transform записан.
    */
   Q_INVOKABLE bool set_transform(const QString& clip_id, double scale,
                                  double offset_x, double offset_y);

   /**
    * @brief Ставит cover-кадрирование выбранному V1.
    * @return true, если клип найден.
    */
   Q_INVOKABLE bool apply_cover();

   /**
    * @brief Удаляет выбранный клип с дорожки.
    * @return true, если клип снят.
    */
   Q_INVOKABLE bool delete_selected_clip();

   /**
    * @brief Отменяет последнее изменение.
    * @return true, если стек не пуст.
    */
   Q_INVOKABLE bool undo();

   /**
    * @brief Запускает воспроизведение.
    */
   Q_INVOKABLE void play();

   /**
    * @brief Останавливает воспроизведение.
    */
   Q_INVOKABLE void pause();

   /**
    * @brief Переключает воспроизведение.
    */
   Q_INVOKABLE void toggle_play();

   /**
    * @brief Пишет json на диск.
    * @return true, если файл записан.
    */
   Q_INVOKABLE bool save();

   /**
    * @brief Возвращает id клипа.
    * @param index - индекс среди всех клипов.
    * @return id или пусто.
    */
   Q_INVOKABLE QString clip_id_at(int index) const;

   /**
    * @brief Возвращает дорожку клипа.
    * @param clip_id - клип.
    * @return v1, v2, a1 или пусто.
    */
   Q_INVOKABLE QString clip_track(const QString& clip_id) const;

   /**
    * @brief Возвращает вход клипа.
    * @param clip_id - клип.
    * @return миллисекунды.
    */
   Q_INVOKABLE qint64 clip_in(const QString& clip_id) const;

   /**
    * @brief Возвращает выход клипа.
    * @param clip_id - клип.
    * @return миллисекунды.
    */
   Q_INVOKABLE qint64 clip_out(const QString& clip_id) const;

   /**
    * @brief Возвращает старт клипа на таймлайне.
    * @param clip_id - клип.
    * @return миллисекунды.
    */
   Q_INVOKABLE qint64 clip_start(const QString& clip_id) const;

   /**
    * @brief Возвращает громкость.
    * @param clip_id - клип.
    * @return коэффициент.
    */
   Q_INVOKABLE double clip_volume(const QString& clip_id) const;

   /**
    * @brief Возвращает масштаб.
    * @param clip_id - клип.
    * @return множитель.
    */
   Q_INVOKABLE double clip_scale(const QString& clip_id) const;

   /**
    * @brief Возвращает сдвиг X.
    * @param clip_id - клип.
    * @return смещение.
    */
   Q_INVOKABLE double clip_offset_x(const QString& clip_id) const;

   /**
    * @brief Возвращает сдвиг Y.
    * @param clip_id - клип.
    * @return смещение.
    */
   Q_INVOKABLE double clip_offset_y(const QString& clip_id) const;

   /**
    * @brief Возвращает текст клипа.
    * @param clip_id - клип.
    * @return строка.
    */
   Q_INVOKABLE QString clip_text(const QString& clip_id) const;

   /**
    * @brief Возвращает id первого клипа дорожки.
    * @param track - v1, v2 или a1.
    * @return id или пусто.
    */
   Q_INVOKABLE QString first_clip_on(const QString& track) const;

   /**
    * @brief Абсолютный путь файла клипа.
    * @param clip_id - клип.
    * @return путь или пусто.
    */
   Q_INVOKABLE QString clip_abs_path(const QString& clip_id) const;

   /**
    * @brief Клип V1, покрывающий время таймлайна.
    * @param time_ms - ползунок.
    * @return указатель или nullptr.
    */
   const TimelineClip* video_at(qint64 time_ms) const;

   /**
    * @brief Клипы V2 в это время.
    * @param time_ms - ползунок.
    * @return клипы текста.
    */
   std::vector<const TimelineClip*> overlays_at(qint64 time_ms) const;

   /**
    * @brief Длительность таймлайна.
    * @return миллисекунды.
    */
   qint64 duration_ms() const;

   /**
    * @brief Путь проекта.
    * @return json ролика.
    */
   QString project_path() const;

   /**
    * @brief Пики волны ассета.
    * @param asset_id - ассет.
    * @return есть ли кэш.
    */
   Q_INVOKABLE bool has_waveform(const QString& asset_id) const;

   /**
    * @brief Коэффициент громкости, который читает экспортёр.
    * @param clip_id - клип.
    * @return volume клипа.
    */
   Q_INVOKABLE double export_volume(const QString& clip_id) const {
      return clip_volume(clip_id);
   }

 signals:
   void store_changed();
   void short_changed();
   void timeline_changed();
   void playhead_changed();
   void playing_changed();
   void selection_changed();
   void recovery_changed();

 private:
   TimelineClip* mutable_clip(const QString& id);
   const TimelineClip* clip_by_id(const QString& id) const;
   int count_track(const QString& track) const;
   void push_undo();
   void load_json();
   QJsonObject to_json() const;
   void from_json(const QJsonObject& object);
   bool attach_media(const QString& short_id, const QString& path,
                     bool keep_name);
   QString write_poster(const QString& short_id, const QString& file);
   void write_waveform(const QString& asset_id, const QString& file);
   void tick_play();
   void overwrite_range(const QString& track, qint64 start_ms,
                        qint64 end_ms);
   QString default_track(const QString& kind) const;
   QString recovery_path() const;
   void schedule_recovery();
   void write_recovery();
   void clear_recovery();
   QJsonObject read_json_file(const QString& path) const;

   CLibraryStore* store_ = nullptr;
   QString short_id_;
   std::vector<TimelineClip> clips_;
   std::vector<QByteArray> undo_;
   qint64 playhead_ms_ = 0;
   bool playing_ = false;
   QString selected_clip_id_;
   QTimer play_timer_;
   QTimer recovery_timer_;
   bool suppress_recovery_ = false;
};
