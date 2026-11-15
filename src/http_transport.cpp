#include "http_transport.h"

#include <QEventLoop>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>

QString http_api_message(const HttpResponse& response) {
   const QJsonDocument document =
       QJsonDocument::fromJson(response.body);
   const QJsonObject object = document.object();
   const QString nested =
       object.value(QStringLiteral("error"))
           .toObject()
           .value(QStringLiteral("message"))
           .toString()
           .trimmed();
   if (!nested.isEmpty()) {
      return nested;
   }
   const QString top =
       object.value(QStringLiteral("message")).toString().trimmed();
   if (!top.isEmpty()) {
      return top;
   }
   if (response.status >= 400) {
      return QStringLiteral("HTTP %1").arg(response.status);
   }
   return {};
}

CHttpTransport::CHttpTransport(QObject* parent) : QObject(parent) {}

void CHttpTransport::use_stub() {
   stub_ = true;
}

void CHttpTransport::apply_pending_headers(HttpResponse* response) {
   if (response == nullptr) {
      return;
   }
   if (!pending_location_.isEmpty()) {
      response->location = pending_location_;
      pending_location_.clear();
   }
   if (pending_status_ > 0) {
      response->status = pending_status_;
      pending_status_ = 0;
   }
}

void CHttpTransport::enqueue_json(const QString& json) {
   HttpResponse response;
   response.status = 200;
   response.body = json.toUtf8();
   apply_pending_headers(&response);
   queue_.push_back(response);
}

void CHttpTransport::enqueue_file(const QString& path) {
   QFile file(path);
   HttpResponse response;
   if (!file.open(QIODevice::ReadOnly)) {
      response.error = QStringLiteral("stub file missing");
      apply_pending_headers(&response);
      queue_.push_back(response);
      return;
   }
   response.status = 200;
   response.body = file.readAll();
   apply_pending_headers(&response);
   queue_.push_back(response);
}

void CHttpTransport::enqueue_error(const QString& error) {
   HttpResponse response;
   response.error = error;
   apply_pending_headers(&response);
   queue_.push_back(response);
}

void CHttpTransport::enqueue_header(const QString& name,
                                    const QString& value) {
   if (name.compare(QStringLiteral("Location"),
                    Qt::CaseInsensitive) == 0) {
      pending_location_ = value;
   }
}

void CHttpTransport::enqueue_status(int status) {
   pending_status_ = status;
}

void CHttpTransport::clear() {
   queue_.clear();
   call_count_ = 0;
   chat_count_ = 0;
   speech_count_ = 0;
   kling_count_ = 0;
   google_count_ = 0;
   last_url_.clear();
   last_location_.clear();
   last_body_.clear();
   urls_.clear();
   pending_location_.clear();
   pending_status_ = 0;
   aborted_ = false;
   emit log_changed();
}

void CHttpTransport::abort() {
   aborted_ = true;
   emit abort_requested();
}

void CHttpTransport::clear_abort() {
   aborted_ = false;
}

void CHttpTransport::record(const QString& url,
                            const QByteArray& body) {
   ++call_count_;
   last_url_ = url;
   last_body_ = body;
   urls_.append(url);
   if (url.contains(QLatin1String("/v1/chat/completions"))) {
      ++chat_count_;
   }
   if (url.contains(QLatin1String("/v1/audio/speech"))) {
      ++speech_count_;
   }
   if (url.contains(QLatin1String("klingai.com")) ||
       url.contains(QLatin1String("/text-to-video/")) ||
       url.contains(QLatin1String("/v1/images/")) ||
       url.contains(QLatin1String("/tasks"))) {
      ++kling_count_;
   }
   const bool google_host =
       url.contains(QLatin1String("oauth2.googleapis.com")) ||
       (url.contains(QLatin1String("googleapis.com")) &&
        url.contains(QLatin1String("youtube")));
   if (google_host) {
      ++google_count_;
   }
   emit log_changed();
}

QVariantMap CHttpTransport::to_map(const HttpResponse& response) {
   QVariantMap map;
   map.insert(QStringLiteral("status"), response.status);
   map.insert(QStringLiteral("body"),
              QString::fromUtf8(response.body));
   map.insert(QStringLiteral("error"), response.error);
   map.insert(QStringLiteral("location"), response.location);
   return map;
}

HttpResponse CHttpTransport::post(const QString& url,
                                  const QString& bearer,
                                  const QByteArray& body,
                                  const QString& content_type,
                                  const QVariantMap& headers) {
   record(url, body);
   HttpResponse response;
   if (stub_) {
      response = take_stub();
   } else {
      response = live(QStringLiteral("POST"), url, bearer, body,
                      content_type, headers);
   }
   last_location_ = response.location;
   return response;
}

QVariantMap CHttpTransport::post(const QString& url,
                                 const QString& bearer,
                                 const QString& body,
                                 const QString& content_type) {
   return to_map(post(url, bearer, body.toUtf8(), content_type));
}

HttpResponse CHttpTransport::put(const QString& url,
                                 const QString& bearer,
                                 const QByteArray& body,
                                 const QString& content_type,
                                 const QVariantMap& headers) {
   record(url, body);
   HttpResponse response;
   if (stub_) {
      response = take_stub();
   } else {
      response = live(QStringLiteral("PUT"), url, bearer, body,
                      content_type, headers);
   }
   last_location_ = response.location;
   return response;
}

QVariantMap CHttpTransport::put(const QString& url,
                                const QString& bearer,
                                const QString& body,
                                const QString& content_type) {
   return to_map(put(url, bearer, body.toUtf8(), content_type));
}

HttpResponse CHttpTransport::get_response(const QString& url,
                                          const QString& bearer) {
   record(url, {});
   HttpResponse response;
   if (stub_) {
      response = take_stub();
   } else {
      response = live(QStringLiteral("GET"), url, bearer, {}, {}, {});
   }
   last_location_ = response.location;
   return response;
}

QVariantMap CHttpTransport::get(const QString& url,
                                const QString& bearer) {
   return to_map(get_response(url, bearer));
}

HttpResponse CHttpTransport::take_stub() {
   if (aborted_) {
      HttpResponse response;
      response.error = QStringLiteral("cancelled");
      return response;
   }
   if (queue_.empty()) {
      HttpResponse response;
      response.error = QStringLiteral("stub empty");
      return response;
   }
   const HttpResponse response = queue_.front();
   queue_.erase(queue_.begin());
   return response;
}

HttpResponse CHttpTransport::live(const QString& method,
                                  const QString& url,
                                  const QString& bearer,
                                  const QByteArray& body,
                                  const QString& content_type,
                                  const QVariantMap& headers) {
   aborted_ = false;
   QNetworkAccessManager manager;
   QNetworkRequest request{QUrl(url)};
   if (method != QLatin1String("GET")) {
      const QString type = content_type.trimmed().isEmpty()
          ? QStringLiteral("application/json")
          : content_type;
      request.setHeader(QNetworkRequest::ContentTypeHeader, type);
   }
   if (!bearer.isEmpty()) {
      request.setRawHeader(
          "Authorization",
          QByteArray("Bearer ") + bearer.toUtf8());
   }
   for (auto it = headers.constBegin(); it != headers.constEnd();
        ++it) {
      request.setRawHeader(it.key().toUtf8(),
                           it.value().toString().toUtf8());
   }
   QNetworkReply* reply = nullptr;
   if (method == QLatin1String("GET")) {
      reply = manager.get(request);
   } else if (method == QLatin1String("PUT")) {
      reply = manager.put(request, body);
   } else {
      reply = manager.post(request, body);
   }
   QEventLoop loop;
   QObject::connect(reply, &QNetworkReply::finished, &loop,
                    &QEventLoop::quit);
   QObject::connect(this, &CHttpTransport::abort_requested, reply,
                    &QNetworkReply::abort);
   loop.exec();
   HttpResponse response;
   if (aborted_ ||
       reply->error() == QNetworkReply::OperationCanceledError) {
      response.error = QStringLiteral("cancelled");
      reply->deleteLater();
      return response;
   }
   response.status =
       reply->attribute(QNetworkRequest::HttpStatusCodeAttribute)
           .toInt();
   response.body = reply->readAll();
   response.location =
       QString::fromUtf8(reply->rawHeader("Location"));
   if (reply->error() != QNetworkReply::NoError &&
       response.body.isEmpty()) {
      response.error = reply->errorString();
   }
   reply->deleteLater();
   return response;
}
