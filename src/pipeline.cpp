#include "pipeline.h"

#include "chat_tool.h"
#include "speech_tool.h"

#include <QFile>
#include <QTimer>
#include <QUuid>

namespace {

constexpr char kStepText[] = "text";
constexpr char kStepVoice[] = "voice";

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

bool CPipeline::prepare_run(const QString& short_id,
                            bool allow_existing_script) {
   needs_settings_message_.clear();
   last_error_.clear();
   cancelled_ = false;
   if (store_ == nullptr || secrets_ == nullptr ||
       transport_ == nullptr) {
      last_error_ = QStringLiteral("no pipeline");
      emit progress_changed();
      return false;
   }
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
   skip_text_ = allow_existing_script && !script.isEmpty();
   short_id_ = short_id;
   const QString first_step = QString::fromLatin1(
       skip_text_ ? kStepVoice : kStepText);
   task_id_ = store_->start_task(short_id_, first_step);
   store_->set_short_status(short_id_, QStringLiteral("generating"));
   running_ = true;
   progress_ = skip_text_ ? 50 : 0;
   step_ = first_step;
   emit progress_changed();
   return true;
}

bool CPipeline::run(const QString& short_id) {
   if (!prepare_run(short_id, false)) {
      return false;
   }
   QTimer::singleShot(0, this, [this]() {
      if (skip_text_) {
         run_voice_step();
      } else {
         run_text_step();
      }
   });
   return true;
}

bool CPipeline::retry(const QString& short_id) {
   const QString script =
       store_ == nullptr ? QString()
                         : store_->short_script(short_id);
   if (!prepare_run(short_id, !script.trimmed().isEmpty())) {
      return false;
   }
   QTimer::singleShot(0, this, [this]() {
      if (skip_text_) {
         run_voice_step();
      } else {
         run_text_step();
      }
   });
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
   if (!running_ || step_ != QLatin1String(kStepVoice)) {
      return;
   }
   QTimer::singleShot(0, this, [this]() { run_voice_step(); });
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
   finish_ok();
}

void CPipeline::finish_ok() {
   running_ = false;
   progress_ = 100;
   store_->update_task(task_id_, step_, QStringLiteral("done"), 100,
                       {});
   store_->set_short_status(short_id_, QStringLiteral("draft"));
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
