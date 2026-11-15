#include "video_tool.h"

#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QObject>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <QUuid>

namespace {

constexpr int kMaxPolls = 300;
constexpr int kPollMs = 2000;

QString trim_root(QString root) {
   while (root.endsWith(QLatin1Char('/'))) {
      root.chop(1);
   }
   return root;
}

QString json_status(const QJsonObject& object) {
   const QString status =
       object.value(QStringLiteral("status")).toString();
   if (!status.isEmpty()) {
      return status;
   }
   return object.value(QStringLiteral("task_status")).toString();
}

QString json_id(const QJsonObject& object) {
   const QString id = object.value(QStringLiteral("id")).toString();
   if (!id.isEmpty()) {
      return id;
   }
   return object.value(QStringLiteral("task_id")).toString();
}

QString output_url(const QJsonObject& object) {
   const QJsonArray outputs =
       object.value(QStringLiteral("outputs")).toArray();
   for (const QJsonValue& value : outputs) {
      const QJsonObject item = value.toObject();
      const QString type =
          item.value(QStringLiteral("type")).toString();
      const QString url = item.value(QStringLiteral("url")).toString();
      if (url.isEmpty()) {
         continue;
      }
      if (type.isEmpty() || type == QLatin1String("video")) {
         return url;
      }
   }
   const QJsonArray videos = object.value(QStringLiteral("task_result"))
                                 .toObject()
                                 .value(QStringLiteral("videos"))
                                 .toArray();
   if (!videos.isEmpty()) {
      return videos.at(0).toObject().value(QStringLiteral("url"))
          .toString();
   }
   return {};
}

QJsonObject task_object(const QJsonDocument& document) {
   const QJsonObject root = document.object();
   const QJsonValue data = root.value(QStringLiteral("data"));
   if (data.isArray() && !data.toArray().isEmpty()) {
      return data.toArray().at(0).toObject();
   }
   if (data.isObject()) {
      return data.toObject();
   }
   return root;
}

bool is_success(const QString& status) {
   return status == QLatin1String("succeeded") ||
          status == QLatin1String("succeed") ||
          status == QLatin1String("success");
}

bool is_failure(const QString& status) {
   return status == QLatin1String("failed") ||
          status == QLatin1String("fail") ||
          status == QLatin1String("error");
}

}  // namespace

CVideoTool::CVideoTool(CHttpTransport* transport,
                       CSecretStore* secrets)
    : transport_(transport), secrets_(secrets) {}

bool CVideoTool::wait_poll() {
   if (transport_ == nullptr) {
      return false;
   }
   QEventLoop loop;
   QTimer timer;
   timer.setSingleShot(true);
   QObject::connect(&timer, &QTimer::timeout, &loop,
                    &QEventLoop::quit);
   QObject::connect(transport_, &CHttpTransport::abort_requested,
                    &loop, &QEventLoop::quit);
   timer.start(kPollMs);
   loop.exec();
   return !cancelled_;
}

QString CVideoTool::poll_video_url(const QString& task_id,
                                   QString& error) {
   const QString root = trim_root(secrets_->kling_base_url());
   const QString url =
       root + QStringLiteral("/tasks?task_ids=") + task_id;
   const QString key = secrets_->secret_kling_api_key();
   for (int i = 0; i < kMaxPolls; ++i) {
      if (cancelled_) {
         error = QStringLiteral("cancelled");
         return {};
      }
      const HttpResponse response =
          transport_->get_response(url, key);
      if (!response.error.isEmpty()) {
         error = response.error;
         return {};
      }
      const QString api_error = http_api_message(response);
      if (response.status >= 400) {
         error = api_error.isEmpty() ? QStringLiteral("video poll")
                                     : api_error;
         return {};
      }
      const QJsonDocument document =
          QJsonDocument::fromJson(response.body);
      const QJsonObject task = task_object(document);
      const QString status = json_status(task);
      if (is_success(status)) {
         const QString file_url = output_url(task);
         if (file_url.isEmpty()) {
            error = QStringLiteral("empty video url");
            return {};
         }
         return file_url;
      }
      if (is_failure(status)) {
         error = api_error.isEmpty() ? QStringLiteral("video failed")
                                     : api_error;
         return {};
      }
      if (!wait_poll()) {
         error = QStringLiteral("cancelled");
         return {};
      }
   }
   error = QStringLiteral("video timeout");
   return {};
}

QString CVideoTool::download_file(const QString& url, QString& error) {
   const HttpResponse response = transport_->get_response(url, {});
   if (!response.error.isEmpty()) {
      error = response.error;
      return {};
   }
   if (response.status >= 400 || response.body.isEmpty()) {
      error = QStringLiteral("video download");
      return {};
   }
   const QString path = QDir::temp().filePath(
       QStringLiteral("yc-video-") +
       QUuid::createUuid().toString(QUuid::WithoutBraces) +
       QStringLiteral(".mp4"));
   QFile file(path);
   if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
      error = QStringLiteral("video file");
      return {};
   }
   file.write(response.body);
   return path;
}

QString CVideoTool::run(const QString& prompt, int duration_s,
                        QString& error) {
   error.clear();
   cancelled_ = false;
   if (transport_ == nullptr || secrets_ == nullptr) {
      error = QStringLiteral("no transport");
      return {};
   }
   QObject guard;
   QObject::connect(transport_, &CHttpTransport::abort_requested,
                    &guard, [this]() { cancelled_ = true; });
   QJsonObject watermark;
   watermark.insert(QStringLiteral("enabled"), false);
   QJsonObject options;
   options.insert(QStringLiteral("watermark_info"), watermark);
   QJsonObject settings;
   settings.insert(QStringLiteral("aspect_ratio"),
                   QStringLiteral("9:16"));
   settings.insert(QStringLiteral("resolution"),
                   QStringLiteral("720p"));
   QJsonObject payload;
   payload.insert(QStringLiteral("prompt"), prompt);
   payload.insert(QStringLiteral("duration"), duration_s);
   payload.insert(QStringLiteral("settings"), settings);
   payload.insert(QStringLiteral("options"), options);
   const QString root = trim_root(secrets_->kling_base_url());
   const QString url = root + QStringLiteral("/text-to-video/") +
                       secrets_->kling_model();
   const HttpResponse response = transport_->post(
       url, secrets_->secret_kling_api_key(),
       QJsonDocument(payload).toJson(QJsonDocument::Compact));
   if (cancelled_) {
      error = QStringLiteral("cancelled");
      return {};
   }
   if (!response.error.isEmpty()) {
      error = response.error;
      return {};
   }
   const QString api_error = http_api_message(response);
   if (response.status >= 400) {
      error = api_error.isEmpty() ? QStringLiteral("empty video")
                                  : api_error;
      return {};
   }
   const QJsonDocument document =
       QJsonDocument::fromJson(response.body);
   const QString task_id = json_id(task_object(document));
   if (task_id.isEmpty()) {
      error = QStringLiteral("empty video task");
      return {};
   }
   const QString file_url = poll_video_url(task_id, error);
   if (file_url.isEmpty()) {
      return {};
   }
   return download_file(file_url, error);
}
