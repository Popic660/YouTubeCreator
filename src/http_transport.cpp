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
   const QString message =
       document.object()
           .value(QStringLiteral("error"))
           .toObject()
           .value(QStringLiteral("message"))
           .toString()
           .trimmed();
   if (!message.isEmpty()) {
      return message;
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

void CHttpTransport::enqueue_json(const QString& json) {
   HttpResponse response;
   response.status = 200;
   response.body = json.toUtf8();
   queue_.push_back(response);
}

void CHttpTransport::enqueue_file(const QString& path) {
   QFile file(path);
   HttpResponse response;
   if (!file.open(QIODevice::ReadOnly)) {
      response.error = QStringLiteral("stub file missing");
      queue_.push_back(response);
      return;
   }
   response.status = 200;
   response.body = file.readAll();
   queue_.push_back(response);
}

void CHttpTransport::enqueue_error(const QString& error) {
   HttpResponse response;
   response.error = error;
   queue_.push_back(response);
}

void CHttpTransport::clear() {
   queue_.clear();
   call_count_ = 0;
   chat_count_ = 0;
   speech_count_ = 0;
   last_url_.clear();
   last_body_.clear();
   aborted_ = false;
   emit log_changed();
}

void CHttpTransport::abort() {
   aborted_ = true;
   emit abort_requested();
}

void CHttpTransport::record(const QString& url,
                            const QByteArray& body) {
   ++call_count_;
   last_url_ = url;
   last_body_ = body;
   if (url.contains(QLatin1String("/v1/chat/completions"))) {
      ++chat_count_;
   }
   if (url.contains(QLatin1String("/v1/audio/speech"))) {
      ++speech_count_;
   }
   emit log_changed();
}

HttpResponse CHttpTransport::post(const QString& url,
                                  const QString& bearer,
                                  const QByteArray& body) {
   aborted_ = false;
   record(url, body);
   if (stub_) {
      return post_stub();
   }
   return post_live(url, bearer, body);
}

HttpResponse CHttpTransport::post_stub() {
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

HttpResponse CHttpTransport::post_live(const QString& url,
                                       const QString& bearer,
                                       const QByteArray& body) {
   QNetworkAccessManager manager;
   QNetworkRequest request{QUrl(url)};
   request.setHeader(QNetworkRequest::ContentTypeHeader,
                     QStringLiteral("application/json"));
   if (!bearer.isEmpty()) {
      request.setRawHeader(
          "Authorization",
          QByteArray("Bearer ") + bearer.toUtf8());
   }
   QNetworkReply* reply = manager.post(request, body);
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
   if (reply->error() != QNetworkReply::NoError &&
       response.body.isEmpty()) {
      response.error = reply->errorString();
   }
   reply->deleteLater();
   return response;
}
