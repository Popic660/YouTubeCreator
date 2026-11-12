#include "speech_tool.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUuid>

CSpeechTool::CSpeechTool(CHttpTransport* transport,
                         CSecretStore* secrets)
    : transport_(transport), secrets_(secrets) {}

QString CSpeechTool::run(const QString& script, QString& error) {
   error.clear();
   if (transport_ == nullptr || secrets_ == nullptr) {
      error = QStringLiteral("no transport");
      return {};
   }
   QJsonObject payload;
   payload.insert(QStringLiteral("model"), secrets_->tts_model());
   payload.insert(QStringLiteral("input"), script);
   payload.insert(QStringLiteral("voice"), secrets_->voice());
   QString root = secrets_->base_url().trimmed();
   while (root.endsWith(QLatin1Char('/'))) {
      root.chop(1);
   }
   const QString url = root + QStringLiteral("/v1/audio/speech");
   const HttpResponse response = transport_->post(
       url, secrets_->secret_api_key(),
       QJsonDocument(payload).toJson(QJsonDocument::Compact));
   if (!response.error.isEmpty()) {
      error = response.error;
      return {};
   }
   const QString api_error = http_api_message(response);
   if (response.status >= 400 ||
       response.body.trimmed().startsWith('{')) {
      error = api_error.isEmpty() ? QStringLiteral("empty speech")
                                  : api_error;
      return {};
   }
   if (response.body.isEmpty()) {
      error = QStringLiteral("empty speech");
      return {};
   }
   const QString path =
       QDir::temp().filePath(
           QStringLiteral("yc-voice-") +
           QUuid::createUuid().toString(QUuid::WithoutBraces) +
           QStringLiteral(".wav"));
   QFile file(path);
   if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
      error = QStringLiteral("speech file");
      return {};
   }
   file.write(response.body);
   return path;
}
