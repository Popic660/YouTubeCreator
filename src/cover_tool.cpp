#include "cover_tool.h"

#include "media_io.h"

#include <QDir>
#include <QEventLoop>
#include <QFileInfo>
#include <QObject>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>

namespace {

constexpr int kMaxPolls = 300;
constexpr int kPollMs = 2000;
constexpr int kCoverWidth = 1280;
constexpr int kCoverHeight = 720;

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

QString image_url(const QJsonObject& object) {
   const QJsonArray images = object.value(QStringLiteral("task_result"))
                                 .toObject()
                                 .value(QStringLiteral("images"))
                                 .toArray();
   if (!images.isEmpty()) {
      return images.at(0)
          .toObject()
          .value(QStringLiteral("url"))
          .toString();
   }
   const QJsonArray outputs =
       object.value(QStringLiteral("outputs")).toArray();
   if (!outputs.isEmpty()) {
      return outputs.at(0)
          .toObject()
          .value(QStringLiteral("url"))
          .toString();
   }
   return {};
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

CCoverTool::CCoverTool(CHttpTransport* transport,
                       CSecretStore* secrets)
    : transport_(transport), secrets_(secrets) {}

bool CCoverTool::wait_poll() {
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

QString CCoverTool::poll_image_url(const QString& task_id,
                                   QString& error) {
   const QString root = trim_root(secrets_->kling_base_url());
   const QString url =
       root + QStringLiteral("/v1/images/generations/") + task_id;
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
         error = api_error.isEmpty() ? QStringLiteral("cover poll")
                                     : api_error;
         return {};
      }
      const QJsonDocument document =
          QJsonDocument::fromJson(response.body);
      const QJsonObject task = task_object(document);
      const QString status = json_status(task);
      if (is_success(status)) {
         const QString file_url = image_url(task);
         if (file_url.isEmpty()) {
            error = QStringLiteral("empty cover url");
            return {};
         }
         return file_url;
      }
      if (is_failure(status)) {
         error = api_error.isEmpty() ? QStringLiteral("cover failed")
                                     : api_error;
         return {};
      }
      if (!wait_poll()) {
         error = QStringLiteral("cancelled");
         return {};
      }
   }
   error = QStringLiteral("cover timeout");
   return {};
}

QString CCoverTool::save_cover(const QByteArray& bytes,
                               const QString& library_root,
                               const QString& short_id,
                               QString& error) {
   QImage image = QImage::fromData(bytes);
   if (image.isNull()) {
      error = QStringLiteral("cover image");
      return {};
   }
   const QSize target(kCoverWidth, kCoverHeight);
   if (image.size() != target) {
      image = image.scaled(target, Qt::KeepAspectRatioByExpanding,
                           Qt::SmoothTransformation);
      const int x = (image.width() - kCoverWidth) / 2;
      const int y = (image.height() - kCoverHeight) / 2;
      image = image.copy(x, y, kCoverWidth, kCoverHeight);
   }
   const QString relative =
       QStringLiteral("shorts/") + short_id +
       QStringLiteral("/youtube_cover.jpg");
   const QString dest = QDir(library_root).filePath(relative);
   QDir().mkpath(QFileInfo(dest).absolutePath());
   if (!CMediaIo::write_jpeg(image, dest)) {
      error = QStringLiteral("cover write");
      return {};
   }
   return relative;
}

QString CCoverTool::run(const QString& library_root,
                        const QString& short_id, const QString& prompt,
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
   QJsonObject payload;
   payload.insert(QStringLiteral("model_name"),
                  secrets_->kling_image_model());
   payload.insert(QStringLiteral("prompt"), prompt);
   payload.insert(QStringLiteral("n"), 1);
   payload.insert(QStringLiteral("aspect_ratio"),
                  QStringLiteral("16:9"));
   const QString root = trim_root(secrets_->kling_base_url());
   const QString url =
       root + QStringLiteral("/v1/images/generations");
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
      error = api_error.isEmpty() ? QStringLiteral("empty cover")
                                  : api_error;
      return {};
   }
   const QJsonDocument document =
       QJsonDocument::fromJson(response.body);
   const QString task_id = json_id(task_object(document));
   if (task_id.isEmpty()) {
      error = QStringLiteral("empty cover task");
      return {};
   }
   const QString file_url = poll_image_url(task_id, error);
   if (file_url.isEmpty()) {
      return {};
   }
   const HttpResponse download =
       transport_->get_response(file_url, {});
   if (!download.error.isEmpty()) {
      error = download.error;
      return {};
   }
   if (download.status >= 400 || download.body.isEmpty()) {
      error = QStringLiteral("cover download");
      return {};
   }
   return save_cover(download.body, library_root, short_id, error);
}
