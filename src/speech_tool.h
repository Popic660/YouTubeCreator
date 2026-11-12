#pragma once

#include "http_transport.h"
#include "secret_store.h"

#include <QString>

/**
 * @brief Шаг голоса через audio/speech.
 */
class CSpeechTool {
 public:
   /**
    * @brief Создаёт инструмент речи.
    * @param transport - HTTP.
    * @param secrets - ключ и модели.
    */
   explicit CSpeechTool(CHttpTransport* transport,
                       CSecretStore* secrets);

   /**
    * @brief Синтезирует аудиофайл.
    * @param script - текст сценария.
    * @param error - текст ошибки.
    * @return путь временного файла или пусто.
    */
   QString run(const QString& script, QString& error);

 private:
   CHttpTransport* transport_ = nullptr;
   CSecretStore* secrets_ = nullptr;
};
