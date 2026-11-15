#pragma once

#include "http_transport.h"
#include "library_store.h"
#include "project_document.h"
#include "secret_store.h"

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

/**
 * @brief Конвейер текста, голоса, видео и обложки.
 */
class CPipeline : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(CLibraryStore* store READ store WRITE set_store
                  NOTIFY store_changed)
   Q_PROPERTY(CProjectDocument* document READ document
                  WRITE set_document NOTIFY document_changed)
   Q_PROPERTY(CSecretStore* secrets READ secrets WRITE set_secrets
                  NOTIFY secrets_changed)
   Q_PROPERTY(CHttpTransport* transport READ transport
                  WRITE set_transport NOTIFY transport_changed)
   Q_PROPERTY(QString activeShortId READ active_short_id
                  NOTIFY progress_changed)
   Q_PROPERTY(QString currentStep READ current_step
                  NOTIFY progress_changed)
   Q_PROPERTY(int progress READ progress NOTIFY progress_changed)
   Q_PROPERTY(QString lastError READ last_error
                  NOTIFY progress_changed)
   Q_PROPERTY(bool running READ is_running NOTIFY progress_changed)
   Q_PROPERTY(bool pauseAfterText READ pause_after_text
                  WRITE set_pause_after_text NOTIFY progress_changed)
   Q_PROPERTY(bool pauseAfterVoice READ pause_after_voice
                  WRITE set_pause_after_voice NOTIFY progress_changed)
   Q_PROPERTY(bool pauseAfterVideoScene READ pause_after_video_scene
                  WRITE set_pause_after_video_scene
                  NOTIFY progress_changed)
   Q_PROPERTY(QString needsSettingsMessage READ needs_settings_message
                  NOTIFY progress_changed)

 public:
   /**
    * @brief Создаёт остановленный конвейер.
    * @param parent - владелец.
    */
   explicit CPipeline(QObject* parent = nullptr);

   CLibraryStore* store() const { return store_; }
   CProjectDocument* document() const { return document_; }
   CSecretStore* secrets() const { return secrets_; }
   CHttpTransport* transport() const { return transport_; }
   QString active_short_id() const { return short_id_; }
   QString current_step() const { return step_; }
   int progress() const { return progress_; }
   QString last_error() const { return last_error_; }
   bool is_running() const { return running_; }
   bool pause_after_text() const { return pause_after_text_; }
   bool pause_after_voice() const { return pause_after_voice_; }
   bool pause_after_video_scene() const {
      return pause_after_video_scene_;
   }
   QString needs_settings_message() const {
      return needs_settings_message_;
   }

   /**
    * @brief Подключает библиотеку.
    * @param store - хранилище.
    */
   void set_store(CLibraryStore* store);

   /**
    * @brief Подключает документ таймлайна.
    * @param document - проект.
    */
   void set_document(CProjectDocument* document);

   /**
    * @brief Подключает ключи.
    * @param secrets - хранилище секретов.
    */
   void set_secrets(CSecretStore* secrets);

   /**
    * @brief Подключает HTTP.
    * @param transport - транспорт.
    */
   void set_transport(CHttpTransport* transport);

   /**
    * @brief Останавливает конвейер после текста.
    * @param enabled - true, чтобы ждать resume.
    */
   void set_pause_after_text(bool enabled);

   /**
    * @brief Останавливает конвейер после голоса.
    * @param enabled - true, чтобы ждать resume.
    */
   void set_pause_after_voice(bool enabled);

   /**
    * @brief Останавливает конвейер после одной сцены видео.
    * @param enabled - true, чтобы ждать resume.
    */
   void set_pause_after_video_scene(bool enabled);

   /**
    * @brief Запускает текст, голос, видео и обложку.
    * @param short_id - ролик.
    * @return true, если запуск принят.
    */
   Q_INVOKABLE bool run(const QString& short_id);

   /**
    * @brief Повторяет задачу ролика.
    * @param short_id - ролик.
    * @return true, если запуск принят.
    */
   Q_INVOKABLE bool retry(const QString& short_id);

   /**
    * @brief Отменяет текущий запуск.
    */
   Q_INVOKABLE void cancel();

   /**
    * @brief Продолжает после паузы.
    */
   Q_INVOKABLE void resume();

 signals:
   void store_changed();
   void document_changed();
   void secrets_changed();
   void transport_changed();
   void progress_changed();

 private:
   void run_text_step();
   void run_voice_step();
   void run_video_step();
   void run_cover_step();
   void finish_ok();
   void finish_error(const QString& error);
   void finish_cancelled();
   bool prepare_run(const QString& short_id,
                    bool allow_existing_script);
   void continue_from_current();
   qint64 video_end_ms() const;
   QString first_step() const;

   CLibraryStore* store_ = nullptr;
   CProjectDocument* document_ = nullptr;
   CSecretStore* secrets_ = nullptr;
   CHttpTransport* transport_ = nullptr;
   QString short_id_;
   QString task_id_;
   QString step_;
   QString last_error_;
   QString needs_settings_message_;
   int progress_ = 0;
   bool running_ = false;
   bool cancelled_ = false;
   bool pause_after_text_ = false;
   bool pause_after_voice_ = false;
   bool pause_after_video_scene_ = false;
   bool skip_text_ = false;
   bool skip_voice_ = false;
   bool skip_video_ = false;
   bool skip_cover_ = false;
};
