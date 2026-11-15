#include "pipeline.h"

#include "chat_tool.h"
#include "cover_tool.h"
#include "scene_parser.h"
#include "speech_tool.h"
#include "video_tool.h"

#include <QFile>
#include <QTimer>
#include <QUuid>

namespace {

constexpr char kStepText[] = "text";
constexpr char kStepVoice[] = "voice";
constexpr char kStepVideo[] = "video";
constexpr char kStepCover[] = "cover";

}  // namespace

CPipeline::CPipeline(QObject* parent) : QObject(parent) {}

void CPipeline::set_store(CLibraryStore* store) {
   if (store_ == store) {
      return;
   }
   store_ = store;
   emit store_changed();
}

void CPipeline::set_document(CProjectDocument* document) {
   if (document_ == document) {
      return;
   }
   document_ = document;
   emit document_changed();
}

void CPipeline::set_secrets(CSecretStore* secrets) {
   if (secrets_ == secrets) {
      return;
   }
   secrets_ = secrets;
   emit secrets_changed();
}

void CPipeline::set_transport(CHttpTransport* transport) {
   if (transport_ == transport) {
      return;
   }
   transport_ = transport;
   emit transport_changed();
}

void CPipeline::set_pause_after_text(bool enabled) {
   if (pause_after_text_ == enabled) {
      return;
   }
   pause_after_text_ = enabled;
   emit progress_changed();
}

void CPipeline::set_pause_after_voice(bool enabled) {
   if (pause_after_voice_ == enabled) {
      return;
   }
   pause_after_voice_ = enabled;
   emit progress_changed();
}

void CPipeline::set_pause_after_video_scene(bool enabled) {
   if (pause_after_video_scene_ == enabled) {
      return;
   }
   pause_after_video_scene_ = enabled;
   emit progress_changed();
}

QString CPipeline::first_step() const {
   if (!skip_text_) {
      return QString::fromLatin1(kStepText);
   }
   if (!skip_voice_) {
      return QString::fromLatin1(kStepVoice);
   }
   if (!skip_video_) {
      return QString::fromLatin1(kStepVideo);
   }
   return QString::fromLatin1(kStepCover);
}

qint64 CPipeline::video_end_ms() const {
   if (document_ == nullptr) {
      return 0;
   }
   qint64 end = 0;
   const int count = document_->clip_count_on(QStringLiteral("v1"));
   for (int i = 0; i < count; ++i) {
      const QString id =
          document_->clip_on_at(QStringLiteral("v1"), i);
      const qint64 stop = document_->clip_start(id) +
                          (document_->clip_out(id) -
                           document_->clip_in(id));
      if (stop > end) {
         end = stop;
      }
   }
   return end;
}

bool CPipeline::prepare_run(const QString& short_id,
                            bool allow_existing_script) {
   needs_settings_message_.clear();
   last_error_.clear();
   cancelled_ = false;
   skip_text_ = false;
   skip_voice_ = false;
   skip_video_ = false;
   skip_cover_ = false;
   if (store_ == nullptr || secrets_ == nullptr ||
       transport_ == nullptr) {
      last_error_ = QStringLiteral("no pipeline");
      emit progress_changed();
      return false;
   }
   transport_->clear_abort();
   if (!secrets_->has_key()) {
      needs_settings_message_ =
          QStringLiteral("Нужны настройки");
      last_error_ = needs_settings_message_;
      emit progress_changed();
      return false;
   }
   if (store_->short_name(short_id).isEmpty()) {
      last_error_ = QStringLiteral("no short");
      emit progress_changed();
      return false;
   }
   const QString topic = store_->short_topic(short_id).trimmed();
   const QString script = store_->short_script(short_id).trimmed();
   if (topic.isEmpty() && script.isEmpty()) {
      last_error_ = QStringLiteral("empty topic");
      emit progress_changed();
      return false;
   }
   if (topic.isEmpty() && !allow_existing_script) {
      last_error_ = QStringLiteral("empty topic");
      emit progress_changed();
      return false;
   }
   if (document_ != nullptr && document_->short_id() != short_id) {
      document_->open_short(short_id);
   }
   skip_text_ = allow_existing_script && !script.isEmpty();
   skip_voice_ = allow_existing_script && document_ != nullptr &&
                 document_->clip_count_on(QStringLiteral("a1")) > 0;
   if (skip_text_) {
      const int scenes =
          static_cast<int>(parse_scenes(script).size());
      const int clips = document_ == nullptr
                            ? 0
                            : document_->clip_count_on(
                                  QStringLiteral("v1"));
      skip_video_ = clips >= scenes && scenes > 0;
   }
   skip_cover_ = allow_existing_script &&
                 !store_->short_cover_relpath(short_id).isEmpty();
   short_id_ = short_id;
   const QString step = first_step();
   task_id_ = store_->start_task(short_id_, step);
   store_->set_short_status(short_id_, QStringLiteral("generating"));
   running_ = true;
   if (step == QLatin1String(kStepText)) {
      progress_ = 0;
   } else if (step == QLatin1String(kStepVoice)) {
      progress_ = 50;
   } else if (step == QLatin1String(kStepVideo)) {
      progress_ = 70;
   } else {
      progress_ = 85;
   }
   step_ = step;
   emit progress_changed();
   return true;
}

void CPipeline::continue_from_current() {
   if (skip_text_ && skip_voice_ && skip_video_ && skip_cover_) {
      finish_ok();
      return;
   }
   if (step_ == QLatin1String(kStepText)) {
      run_text_step();
      return;
   }
   if (step_ == QLatin1String(kStepVoice)) {
      run_voice_step();
      return;
   }
   if (step_ == QLatin1String(kStepVideo)) {
      run_video_step();
      return;
   }
   run_cover_step();
}

bool CPipeline::run(const QString& short_id) {
   if (!prepare_run(short_id, false)) {
      return false;
   }
   QTimer::singleShot(0, this, [this]() { continue_from_current(); });
   return true;
}

bool CPipeline::retry(const QString& short_id) {
   const QString script =
       store_ == nullptr ? QString()
                         : store_->short_script(short_id);
   if (!prepare_run(short_id, !script.trimmed().isEmpty())) {
      return false;
   }
   QTimer::singleShot(0, this, [this]() { continue_from_current(); });
   return true;
}

void CPipeline::cancel() {
   cancelled_ = true;
   if (transport_ != nullptr) {
      transport_->abort();
   }
   if (running_) {
      finish_cancelled();
   }
}

void CPipeline::resume() {
   if (!running_) {
      return;
   }
   QTimer::singleShot(0, this, [this]() { continue_from_current(); });
}

void CPipeline::run_text_step() {
   if (!running_ || cancelled_) {
      return;
   }
   CChatTool tool(transport_, secrets_);
   QString error;
   const QString folder = store_->short_folder(short_id_);
   const QString script =
       tool.run(store_->short_topic(short_id_),
                store_->effective_prompt(folder), error);
   if (cancelled_) {
      return;
   }
   if (script.isEmpty()) {
      finish_error(error);
      return;
   }
   store_->set_script(short_id_, script);
   store_->update_task(task_id_, QString::fromLatin1(kStepText),
                       QStringLiteral("running"), 50, {});
   step_ = QString::fromLatin1(kStepVoice);
   progress_ = 50;
   emit progress_changed();
   if (pause_after_text_) {
      return;
   }
   QTimer::singleShot(0, this, [this]() { run_voice_step(); });
}

void CPipeline::run_voice_step() {
   if (!running_ || cancelled_) {
      return;
   }
   if (skip_voice_) {
      step_ = QString::fromLatin1(kStepVideo);
      progress_ = 70;
      emit progress_changed();
      QTimer::singleShot(0, this, [this]() { run_video_step(); });
      return;
   }
   CSpeechTool tool(transport_, secrets_);
   QString error;
   const QString path =
       tool.run(store_->short_script(short_id_), error);
   if (cancelled_) {
      if (!path.isEmpty()) {
         QFile::remove(path);
      }
      return;
   }
   if (path.isEmpty()) {
      finish_error(error);
      return;
   }
   if (document_ == nullptr) {
      QFile::remove(path);
      finish_error(QStringLiteral("no document"));
      return;
   }
   if (document_->short_id() != short_id_) {
      document_->open_short(short_id_);
   }
   const QString asset = document_->import_media({}, path);
   QFile::remove(path);
   if (asset.isEmpty()) {
      finish_error(QStringLiteral("voice ingest"));
      return;
   }
   if (document_->place_asset(asset, QStringLiteral("a1"), 0, false)
           .isEmpty()) {
      finish_error(QStringLiteral("voice place"));
      return;
   }
   store_->update_task(task_id_, QString::fromLatin1(kStepVoice),
                       QStringLiteral("running"), 70, {});
   step_ = QString::fromLatin1(kStepVideo);
   progress_ = 70;
   emit progress_changed();
   if (pause_after_voice_) {
      return;
   }
   QTimer::singleShot(0, this, [this]() { run_video_step(); });
}

void CPipeline::run_video_step() {
   if (!running_ || cancelled_) {
      return;
   }
   if (!secrets_->has_kling_key()) {
      needs_settings_message_ =
          QStringLiteral("Нужны настройки");
      finish_error(needs_settings_message_);
      return;
   }
   if (document_ == nullptr) {
      finish_error(QStringLiteral("no document"));
      return;
   }
   if (document_->short_id() != short_id_) {
      document_->open_short(short_id_);
   }
   const std::vector<Scene> scenes =
       parse_scenes(store_->short_script(short_id_));
   const QString folder = store_->short_folder(short_id_);
   const QString style = store_->effective_prompt(folder);
   int placed = document_->clip_count_on(QStringLiteral("v1"));
   if (skip_video_ || placed >= static_cast<int>(scenes.size())) {
      step_ = QString::fromLatin1(kStepCover);
      progress_ = 85;
      emit progress_changed();
      QTimer::singleShot(0, this, [this]() { run_cover_step(); });
      return;
   }
   CVideoTool tool(transport_, secrets_);
   for (int i = placed; i < static_cast<int>(scenes.size()); ++i) {
      if (cancelled_ || !running_) {
         return;
      }
      QString error;
      QString prompt = scenes.at(static_cast<size_t>(i)).prompt;
      if (!style.isEmpty()) {
         prompt += QLatin1Char('\n') + style;
      }
      const int duration_s =
          scenes.at(static_cast<size_t>(i)).duration_s;
      const QString path = tool.run(prompt, duration_s, error);
      if (cancelled_ || !running_) {
         if (!path.isEmpty()) {
            QFile::remove(path);
         }
         return;
      }
      if (path.isEmpty()) {
         finish_error(error);
         return;
      }
      const QString asset = document_->import_media({}, path);
      QFile::remove(path);
      if (asset.isEmpty()) {
         finish_error(QStringLiteral("video ingest"));
         return;
      }
      const qint64 start = video_end_ms();
      if (document_
              ->place_asset(asset, QStringLiteral("v1"), start, false,
                            false)
              .isEmpty()) {
         finish_error(QStringLiteral("video place"));
         return;
      }
      ++placed;
      store_->update_task(task_id_, QString::fromLatin1(kStepVideo),
                          QStringLiteral("running"), 80, {});
      progress_ = 80;
      emit progress_changed();
      if (pause_after_video_scene_ &&
          i + 1 < static_cast<int>(scenes.size())) {
         return;
      }
   }
   step_ = QString::fromLatin1(kStepCover);
   progress_ = 85;
   emit progress_changed();
   QTimer::singleShot(0, this, [this]() { run_cover_step(); });
}

void CPipeline::run_cover_step() {
   if (!running_ || cancelled_) {
      return;
   }
   if (skip_cover_ ||
       !store_->short_cover_relpath(short_id_).isEmpty()) {
      finish_ok();
      return;
   }
   if (!secrets_->has_kling_key()) {
      needs_settings_message_ =
          QStringLiteral("Нужны настройки");
      finish_error(needs_settings_message_);
      return;
   }
   CCoverTool tool(transport_, secrets_);
   QString error;
   const QString folder = store_->short_folder(short_id_);
   const QString prompt =
       store_->short_topic(short_id_) + QLatin1Char('\n') +
       store_->effective_prompt(folder) +
       QStringLiteral("\n16:9 YouTube cover");
   const QString relative =
       tool.run(store_->root_path(), short_id_, prompt, error);
   if (cancelled_ || !running_) {
      return;
   }
   if (relative.isEmpty()) {
      finish_error(error);
      return;
   }
   store_->set_cover_relpath(short_id_, relative);
   finish_ok();
}

void CPipeline::finish_ok() {
   running_ = false;
   progress_ = 100;
   store_->update_task(task_id_, step_, QStringLiteral("done"), 100,
                       {});
   store_->set_short_status(short_id_, QStringLiteral("ready"));
   emit progress_changed();
}

void CPipeline::finish_error(const QString& error) {
   running_ = false;
   last_error_ = error;
   store_->update_task(task_id_, step_, QStringLiteral("error"),
                       progress_, error);
   store_->set_short_status(short_id_, QStringLiteral("draft"));
   emit progress_changed();
}

void CPipeline::finish_cancelled() {
   running_ = false;
   store_->update_task(task_id_, step_, QStringLiteral("cancelled"),
                       progress_, {});
   store_->set_short_status(short_id_, QStringLiteral("draft"));
   emit progress_changed();
}
