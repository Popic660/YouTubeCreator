#include "publisher.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStringList>
#include <QUrl>
#include <QUrlQuery>
#include <QVariantMap>

namespace {

constexpr int kTitleLimit = 100;
constexpr qint64 kMaxDurationMs = 180000;
constexpr char kUploadUrl[] =
    "https://www.googleapis.com/upload/youtube/v3/videos";
constexpr char kThumbUrl[] =
    "https://www.googleapis.com/upload/youtube/v3/thumbnails/set";
constexpr char kJsonType[] = "application/json; charset=UTF-8";
constexpr char kMp4Type[] = "video/mp4";
constexpr char kJpegType[] = "image/jpeg";

QString clip_title(const QString& title, const QString& fallback) {
   QString text = title.trimmed();
   if (text.isEmpty()) {
      text = fallback.trimmed();
   }
   if (text.isEmpty()) {
      text = QStringLiteral("Short");
   }
   if (text.size() > kTitleLimit) {
      text = text.left(kTitleLimit);
   }
   return text;
}

QString clip_privacy(const QString& privacy) {
   const QString value = privacy.trimmed().toLower();
   if (value == QStringLiteral("public") ||
       value == QStringLiteral("unlisted") ||
       value == QStringLiteral("private")) {
      return value;
   }
   return QStringLiteral("unlisted");
}

}  // namespace

CPublisher::CPublisher(QObject* parent) : QObject(parent) {}

CLibraryStore* CPublisher::store() const {
   return store_;
}

void CPublisher::set_store(CLibraryStore* store) {
   if (store_ == store) {
      return;
   }
   store_ = store;
   emit store_changed();
}

CChannelAuth* CPublisher::auth() const {
   return auth_;
}

void CPublisher::set_auth(CChannelAuth* auth) {
   if (auth_ == auth) {
      return;
   }
   auth_ = auth;
   emit auth_changed();
}

CHttpTransport* CPublisher::transport() const {
   return transport_;
}

void CPublisher::set_transport(CHttpTransport* transport) {
   if (transport_ == transport) {
      return;
   }
   transport_ = transport;
   emit transport_changed();
}

QString CPublisher::last_error() const {
   return last_error_;
}

void CPublisher::set_error(const QString& text) {
   last_error_ = text;
}

QString CPublisher::bearer(const QString& token) const {
   return QStringLiteral("Bearer %1").arg(token);
}

QString CPublisher::response_text(const HttpResponse& response) const {
   const QString api = http_api_message(response);
   if (!api.isEmpty()) {
      return api;
   }
   if (!response.error.isEmpty()) {
      return response.error;
   }
   return QStringLiteral("HTTP %1").arg(response.status);
}

QString CPublisher::publication_id(const QString& short_id,
                                   const QString& channel_id) const {
   if (store_ == nullptr) {
      return {};
   }
   const int count = store_->publication_count(short_id);
   for (int i = 0; i < count; ++i) {
      const QString id = store_->publication_id_at(short_id, i);
      if (store_->publication_channel_id(id) == channel_id) {
         return id;
      }
   }
   return {};
}

bool CPublisher::write_publication(const QString& short_id,
                                   const QString& channel_id,
                                   const QString& video_id,
                                   const QString& privacy,
                                   const QString& status,
                                   const QString& cover_status,
                                   const QString& error) {
   return store_->upsert_publication(short_id, channel_id, video_id,
                                     privacy, status, cover_status,
                                     error);
}

QByteArray CPublisher::snippet_body(const QString& title,
                                    const QString& description,
                                    const QString& privacy) const {
   QJsonObject snippet;
   snippet.insert(QStringLiteral("title"), title);
   snippet.insert(QStringLiteral("description"), description);
   QJsonObject status;
   status.insert(QStringLiteral("privacyStatus"), privacy);
   status.insert(QStringLiteral("selfDeclaredMadeForKids"), false);
   QJsonObject root;
   root.insert(QStringLiteral("snippet"), snippet);
   root.insert(QStringLiteral("status"), status);
   return QJsonDocument(root).toJson(QJsonDocument::Compact);
}

bool CPublisher::is_thumbnail_skip(
    const HttpResponse& response) const {
   if (response.status == 403) {
      return true;
   }
   const QString text = response_text(response).toLower();
   return text.contains(QLatin1String("custom thumbnail"));
}

bool CPublisher::publish(const QString& short_id,
                         const QStringList& channel_ids,
                         const QString& title,
                         const QString& description,
                         const QString& privacy) {
   last_error_.clear();
   if (store_ == nullptr || auth_ == nullptr ||
       transport_ == nullptr) {
      set_error(QStringLiteral("missing bindings"));
      emit finished();
      return false;
   }
   const QString id = short_id.trimmed();
   if (store_->short_status(id) != QStringLiteral("ready") &&
       store_->short_status(id) != QStringLiteral("published")) {
      set_error(QStringLiteral("short is not ready"));
      emit finished();
      return false;
   }
   if (store_->short_duration_ms(id) > kMaxDurationMs) {
      set_error(QStringLiteral("длительность больше 180 секунд"));
      emit finished();
      return false;
   }
   const QString video_path = store_->export_path(id);
   const QFileInfo video_info(video_path);
   if (video_path.isEmpty() || !video_info.isFile()) {
      set_error(QStringLiteral("нет файла экспорта"));
      emit finished();
      return false;
   }
   QStringList channels;
   for (const QString& raw : channel_ids) {
      const QString channel = raw.trimmed();
      if (!channel.isEmpty() && !channels.contains(channel)) {
         channels.append(channel);
      }
   }
   if (channels.isEmpty()) {
      set_error(QStringLiteral("no channels selected"));
      emit finished();
      return false;
   }
   const QString used_title =
       clip_title(title, store_->short_name(id));
   const QString used_privacy = clip_privacy(privacy);
   const QString thumb_path = store_->short_cover_path(id);
   const qint64 file_size = video_info.size();
   bool any = false;
   for (const QString& channel_id : channels) {
      if (upload_channel(id, channel_id, used_title, description,
                         used_privacy, video_path, thumb_path,
                         file_size)) {
         any = true;
      }
   }
   emit finished();
   return any;
}

bool CPublisher::upload_channel(const QString& short_id,
                                const QString& channel_id,
                                const QString& title,
                                const QString& description,
                                const QString& privacy,
                                const QString& video_path,
                                const QString& thumb_path,
                                qint64 file_size) {
   if (store_->quota_remaining() <= 0) {
      set_error(QStringLiteral("квота выгрузок исчерпана"));
      write_publication(short_id, channel_id, {}, privacy,
                        QStringLiteral("error"), {}, last_error_);
      return false;
   }
   const QString token = auth_->access_token(channel_id);
   if (token.isEmpty()) {
      set_error(auth_->last_error().isEmpty()
                    ? QStringLiteral("missing access_token")
                    : auth_->last_error());
      write_publication(short_id, channel_id, {}, privacy,
                        QStringLiteral("error"), {}, last_error_);
      return false;
   }
   QUrl url(QString::fromUtf8(kUploadUrl));
   QUrlQuery query;
   query.addQueryItem(QStringLiteral("uploadType"),
                      QStringLiteral("resumable"));
   query.addQueryItem(QStringLiteral("part"),
                      QStringLiteral("snippet,status"));
   url.setQuery(query);
   QVariantMap headers;
   headers.insert(QStringLiteral("X-Upload-Content-Type"),
                  QString::fromUtf8(kMp4Type));
   headers.insert(QStringLiteral("X-Upload-Content-Length"),
                  QString::number(file_size));
   const HttpResponse start = transport_->post(
       url.toString(QUrl::FullyEncoded), bearer(token),
       snippet_body(title, description, privacy),
       QString::fromUtf8(kJsonType), headers);
   store_->increment_quota();
   if (!start.error.isEmpty() || start.status >= 400 ||
       start.location.isEmpty()) {
      set_error(response_text(start).isEmpty()
                    ? QStringLiteral("missing upload Location")
                    : response_text(start));
      write_publication(short_id, channel_id, {}, privacy,
                        QStringLiteral("error"), {}, last_error_);
      return false;
   }
   QFile video(video_path);
   if (!video.open(QIODevice::ReadOnly)) {
      set_error(QStringLiteral("нет файла экспорта"));
      write_publication(short_id, channel_id, {}, privacy,
                        QStringLiteral("error"), {}, last_error_);
      return false;
   }
   const QByteArray bytes = video.readAll();
   video.close();
   const HttpResponse put = transport_->put(
       start.location, bearer(token), bytes,
       QString::fromUtf8(kMp4Type));
   if (!put.error.isEmpty() || put.status >= 400) {
      set_error(response_text(put));
      write_publication(short_id, channel_id, {}, privacy,
                        QStringLiteral("error"), {}, last_error_);
      return false;
   }
   const QJsonObject inserted =
       QJsonDocument::fromJson(put.body).object();
   const QString video_id =
       inserted.value(QStringLiteral("id")).toString();
   if (video_id.isEmpty()) {
      set_error(QStringLiteral("missing video id"));
      write_publication(short_id, channel_id, {}, privacy,
                        QStringLiteral("error"), {}, last_error_);
      return false;
   }
   QString cover_status;
   if (!thumb_path.isEmpty() && QFileInfo::exists(thumb_path)) {
      QFile thumb(thumb_path);
      if (!thumb.open(QIODevice::ReadOnly)) {
         cover_status = QStringLiteral("failed");
         set_error(QStringLiteral("thumbnail upload failed"));
      } else {
         QUrl thumb_url(QString::fromUtf8(kThumbUrl));
         QUrlQuery thumb_query;
         thumb_query.addQueryItem(QStringLiteral("videoId"),
                                  video_id);
         thumb_url.setQuery(thumb_query);
         const HttpResponse thumb_res = transport_->post(
             thumb_url.toString(QUrl::FullyEncoded), bearer(token),
             thumb.readAll(), QString::fromUtf8(kJpegType));
         if (is_thumbnail_skip(thumb_res)) {
            cover_status = QStringLiteral("skipped");
         } else if (!thumb_res.error.isEmpty() ||
                    thumb_res.status >= 400) {
            cover_status = QStringLiteral("failed");
            set_error(QStringLiteral("thumbnail upload failed"));
         } else {
            cover_status = QStringLiteral("set");
         }
      }
   }
   if (!write_publication(short_id, channel_id, video_id, privacy,
                          QStringLiteral("uploaded"), cover_status,
                          {})) {
      const QString store_error = store_->last_error();
      set_error(store_error.isEmpty() ? QStringLiteral("store failed")
                                      : store_error);
      return false;
   }
   store_->set_short_status(short_id, QStringLiteral("published"));
   return true;
}
