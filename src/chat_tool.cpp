#include "chat_tool.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

CChatTool::CChatTool(CHttpTransport* transport,
                     CSecretStore* secrets)
    : transport_(transport), secrets_(secrets) {}

QString CChatTool::run(const QString& topic, const QString& prompt,
                       QString& error) {
   error.clear();
   if (transport_ == nullptr || secrets_ == nullptr) {
      error = QStringLiteral("no transport");
      return {};
   }
   QJsonObject system_message;
   system_message.insert(QStringLiteral("role"),
                         QStringLiteral("system"));
   system_message.insert(QStringLiteral("content"), prompt);
   QJsonObject user_message;
   user_message.insert(QStringLiteral("role"),
                       QStringLiteral("user"));
   user_message.insert(
       QStringLiteral("content"),
       QStringLiteral("Тема: ") + topic +
           QStringLiteral(
               "\nНапиши сценарий вертикального шортса JSON "
               "{\"scenes\":[{\"prompt\":\"кадр\","
               "\"line\":\"реплика до 120 знаков\","
               "\"duration_s\":5}]}. prompt — картинка, "
               "line — голос за кадром."));
   QJsonArray messages;
   messages.append(system_message);
   messages.append(user_message);
   QJsonObject payload;
   payload.insert(QStringLiteral("model"), secrets_->chat_model());
   payload.insert(QStringLiteral("messages"), messages);
   const QString url =
       secrets_->openai_url(QStringLiteral("chat/completions"));
   const HttpResponse response = transport_->post(
       url, secrets_->secret_api_key(),
       QJsonDocument(payload).toJson(QJsonDocument::Compact));
   if (!response.error.isEmpty()) {
      error = response.error;
      return {};
   }
   const QString api_error = http_api_message(response);
   if (response.status >= 400) {
      error = api_error.isEmpty() ? QStringLiteral("empty chat")
                                  : api_error;
      return {};
   }
   const QJsonDocument document =
       QJsonDocument::fromJson(response.body);
   const QJsonArray choices =
       document.object().value(QStringLiteral("choices")).toArray();
   if (choices.isEmpty()) {
      error = api_error.isEmpty() ? QStringLiteral("empty chat")
                                  : api_error;
      return {};
   }
   const QString content =
       choices.at(0)
           .toObject()
           .value(QStringLiteral("message"))
           .toObject()
           .value(QStringLiteral("content"))
           .toString()
           .trimmed();
   if (content.isEmpty()) {
      error = QStringLiteral("empty script");
      return {};
   }
   return content;
}
