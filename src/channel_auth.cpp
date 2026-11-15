#include "channel_auth.h"

#include "http_transport.h"
#include "library_store.h"
#include "secret_store.h"

#include <QCryptographicHash>
#include <QDesktopServices>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QTcpServer>
#include <QTcpSocket>
#include <QUrl>
#include <QUrlQuery>

namespace {

constexpr char kTokenUrl[] = "https://oauth2.googleapis.com/token";
constexpr char kAuthUrl[] =
    "https://accounts.google.com/o/oauth2/v2/auth";
constexpr char kChannelsUrl[] =
    "https://www.googleapis.com/youtube/v3/channels"
    "?part=snippet&mine=true";
constexpr char kScope[] =
    "https://www.googleapis.com/auth/youtube.upload "
    "https://www.googleapis.com/auth/youtube.readonly "
    "https://www.googleapis.com/auth/yt-analytics.readonly";
constexpr char kFormType[] = "application/x-www-form-urlencoded";

/**
 * @brief Читает query из первой строки HTTP-запроса.
 * @param request - сырой запрос.
 * @return query или пусто.
 */
QUrlQuery request_query(const QByteArray& request) {
   const QByteArray line = request.split('\n').value(0).trimmed();
   const QList<QByteArray> parts = line.split(' ');
   if (parts.size() < 2) {
      return {};
   }
   const QString path = QString::fromUtf8(parts.at(1));
   QUrl url(QStringLiteral("http://127.0.0.1") + path);
   return QUrlQuery(url);
}

}  // namespace

CChannelAuth::CChannelAuth(QObject* parent) : QObject(parent) {}

void CChannelAuth::set_store(CLibraryStore* store) {
   if (store_ == store) {
      return;
   }
   store_ = store;
   emit bindings_changed();
}

void CChannelAuth::set_secrets(CSecretStore* secrets) {
   if (secrets_ == secrets) {
      return;
   }
   secrets_ = secrets;
   emit bindings_changed();
}

void CChannelAuth::set_transport(CHttpTransport* transport) {
   if (transport_ == transport) {
      return;
   }
   transport_ = transport;
   emit bindings_changed();
}

void CChannelAuth::use_stub() {
   stub_ = true;
   stop_loopback();
}

void CChannelAuth::start() {
   last_error_.clear();
   if (store_ == nullptr || !store_->is_opened()) {
      last_error_ = QStringLiteral("library closed");
      emit log_changed();
      return;
   }
   if (secrets_ == nullptr || !secrets_->has_google_client()) {
      last_error_ = QStringLiteral("needs settings");
      emit log_changed();
      return;
   }
   if (stub_) {
      emit log_changed();
      return;
   }
   if (!start_loopback()) {
      last_error_ = QStringLiteral("loopback failed");
      emit log_changed();
      return;
   }
   verifier_ = pkce_verifier();
   const QUrl url(auth_url());
   ++browser_open_count_;
   QDesktopServices::openUrl(url);
   emit log_changed();
}

bool CChannelAuth::complete_with_code(const QString& code) {
   last_error_.clear();
   if (store_ == nullptr || !store_->is_opened()) {
      last_error_ = QStringLiteral("library closed");
      emit log_changed();
      return false;
   }
   if (transport_ == nullptr || secrets_ == nullptr) {
      last_error_ = QStringLiteral("missing bindings");
      emit log_changed();
      return false;
   }
   if (redirect_uri_.isEmpty()) {
      redirect_uri_ = QStringLiteral("http://127.0.0.1:1/");
   }
   if (verifier_.isEmpty()) {
      verifier_ = pkce_verifier();
   }
   const bool ok = exchange_code(code.trimmed());
   emit log_changed();
   return ok;
}

void CChannelAuth::complete_with_error() {
   last_error_ = QStringLiteral("cancelled");
   stop_loopback();
   emit log_changed();
}

bool CChannelAuth::disconnect_channel(const QString& channel_id) {
   const QString id = channel_id.trimmed();
   if (store_ == nullptr || secrets_ == nullptr || id.isEmpty()) {
      return false;
   }
   const bool removed = store_->remove_channel(id);
   secrets_->clear_channel_refresh(id);
   secrets_->save();
   emit log_changed();
   return removed;
}

int CChannelAuth::channel_count() const {
   if (store_ == nullptr) {
      return 0;
   }
   return store_->channel_count();
}

QString CChannelAuth::channel_id_at(int index) const {
   if (store_ == nullptr) {
      return {};
   }
   return store_->channel_id_at(index);
}

QString CChannelAuth::channel_title_at(int index) const {
   if (store_ == nullptr) {
      return {};
   }
   return store_->channel_title_at(index);
}

bool CChannelAuth::exchange_code(const QString& code) {
   if (code.isEmpty()) {
      last_error_ = QStringLiteral("empty code");
      return false;
   }
   const HttpResponse token = transport_->post(
       QString::fromUtf8(kTokenUrl), {}, token_body(code),
       QString::fromUtf8(kFormType));
   if (!token.error.isEmpty() || token.status >= 400) {
      last_error_ = http_api_message(token);
      if (last_error_.isEmpty()) {
         last_error_ = token.error;
      }
      return false;
   }
   const QJsonObject token_json =
       QJsonDocument::fromJson(token.body).object();
   const QString refresh =
       token_json.value(QStringLiteral("refresh_token")).toString();
   const QString access =
       token_json.value(QStringLiteral("access_token")).toString();
   if (refresh.isEmpty()) {
      last_error_ = QStringLiteral("missing refresh_token");
      return false;
   }
   const HttpResponse list = transport_->get_response(
       QString::fromUtf8(kChannelsUrl), access);
   if (!list.error.isEmpty() || list.status >= 400) {
      last_error_ = http_api_message(list);
      if (last_error_.isEmpty()) {
         last_error_ = list.error;
      }
      return false;
   }
   const QJsonArray items =
       QJsonDocument::fromJson(list.body)
           .object()
           .value(QStringLiteral("items"))
           .toArray();
   if (items.isEmpty()) {
      last_error_ = QStringLiteral("no channel");
      return false;
   }
   const QJsonObject item = items.at(0).toObject();
   const QString id = item.value(QStringLiteral("id")).toString();
   const QString title = item.value(QStringLiteral("snippet"))
                             .toObject()
                             .value(QStringLiteral("title"))
                             .toString();
   if (id.isEmpty() || title.isEmpty()) {
      last_error_ = QStringLiteral("empty channel");
      return false;
   }
   if (!store_->upsert_channel(id, title)) {
      last_error_ = QStringLiteral("store failed");
      return false;
   }
   secrets_->set_channel_refresh(id, refresh);
   secrets_->save();
   return true;
}

QByteArray CChannelAuth::token_body(const QString& code) const {
   QUrlQuery query;
   query.addQueryItem(QStringLiteral("code"), code);
   query.addQueryItem(QStringLiteral("client_id"),
                      secrets_->google_client_id());
   query.addQueryItem(QStringLiteral("client_secret"),
                      secrets_->secret_google_client_secret());
   query.addQueryItem(QStringLiteral("redirect_uri"), redirect_uri_);
   query.addQueryItem(QStringLiteral("grant_type"),
                      QStringLiteral("authorization_code"));
   query.addQueryItem(QStringLiteral("code_verifier"), verifier_);
   return query.query(QUrl::FullyEncoded).toUtf8();
}

QString CChannelAuth::auth_url() const {
   QUrl url(QString::fromUtf8(kAuthUrl));
   QUrlQuery query;
   query.addQueryItem(QStringLiteral("client_id"),
                      secrets_->google_client_id());
   query.addQueryItem(QStringLiteral("redirect_uri"), redirect_uri_);
   query.addQueryItem(QStringLiteral("response_type"),
                      QStringLiteral("code"));
   query.addQueryItem(QStringLiteral("scope"),
                      QString::fromUtf8(kScope));
   query.addQueryItem(QStringLiteral("access_type"),
                      QStringLiteral("offline"));
   query.addQueryItem(QStringLiteral("prompt"),
                      QStringLiteral("consent select_account"));
   query.addQueryItem(QStringLiteral("include_granted_scopes"),
                      QStringLiteral("true"));
   query.addQueryItem(QStringLiteral("code_challenge"),
                      pkce_challenge(verifier_));
   query.addQueryItem(QStringLiteral("code_challenge_method"),
                      QStringLiteral("S256"));
   url.setQuery(query);
   return url.toString();
}

bool CChannelAuth::start_loopback() {
   stop_loopback();
   server_ = new QTcpServer(this);
   if (!server_->listen(QHostAddress::LocalHost, 0)) {
      delete server_;
      server_ = nullptr;
      return false;
   }
   redirect_uri_ = QStringLiteral("http://127.0.0.1:%1/")
                       .arg(server_->serverPort());
   QObject::connect(server_, &QTcpServer::newConnection, this,
                    &CChannelAuth::on_connection);
   return true;
}

void CChannelAuth::stop_loopback() {
   if (server_ == nullptr) {
      return;
   }
   server_->close();
   server_->deleteLater();
   server_ = nullptr;
}

void CChannelAuth::on_connection() {
   if (server_ == nullptr) {
      return;
   }
   QTcpSocket* socket = server_->nextPendingConnection();
   if (socket == nullptr) {
      return;
   }
   QObject::connect(socket, &QTcpSocket::readyRead, this, [this,
                                                            socket]() {
      const QByteArray request = socket->readAll();
      const QUrlQuery query = request_query(request);
      const QString code =
          query.queryItemValue(QStringLiteral("code"));
      const QString error =
          query.queryItemValue(QStringLiteral("error"));
      if (!error.isEmpty() || code.isEmpty()) {
         reply_html(socket, QStringLiteral("Вход отменён."));
         complete_with_error();
         return;
      }
      reply_html(socket, QStringLiteral("Можно закрыть окно."));
      complete_with_code(code);
      stop_loopback();
   });
}

void CChannelAuth::reply_html(QTcpSocket* socket,
                              const QString& body) {
   const QByteArray html =
       QByteArray("<html><body>") + body.toUtf8() +
       QByteArray("</body></html>");
   QByteArray response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; "
                         "charset=utf-8\r\nContent-Length: ";
   response += QByteArray::number(html.size());
   response += "\r\nConnection: close\r\n\r\n";
   response += html;
   socket->write(response);
   socket->disconnectFromHost();
   socket->deleteLater();
}

QString CChannelAuth::pkce_verifier() {
   static constexpr char kChars[] =
       "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
       "-._~";
   QString out;
   out.resize(64);
   auto* rng = QRandomGenerator::global();
   for (int i = 0; i < 64; ++i) {
      out[i] = QLatin1Char(kChars[rng->bounded(66)]);
   }
   return out;
}

QString CChannelAuth::pkce_challenge(const QString& verifier) {
   const QByteArray hash = QCryptographicHash::hash(
       verifier.toLatin1(), QCryptographicHash::Sha256);
   return QString::fromLatin1(
       hash.toBase64(QByteArray::Base64UrlEncoding |
                     QByteArray::OmitTrailingEquals));
}
