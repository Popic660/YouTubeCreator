#pragma once

#include "http_transport.h"
#include "secret_store.h"

#include <QString>

/**
 * @brief Шаг текста через chat completions.
 */
class CChatTool {
 public:
   /**
    * @brief Создаёт инструмент чата.
    * @param transport - HTTP.
    * @param secrets - ключ и модели.
    */
   explicit CChatTool(CHttpTransport* transport, CSecretStore* secrets);

   /**
    * @brief Запрашивает сценарий.
    * @param topic - тема ролика.
    * @param prompt - эффективный промпт папки.
    * @param error - текст ошибки.
    * @return сценарий или пусто.
    */
   QString run(const QString& topic, const QString& prompt,
               QString& error);

 private:
   CHttpTransport* transport_ = nullptr;
   CSecretStore* secrets_ = nullptr;
};
