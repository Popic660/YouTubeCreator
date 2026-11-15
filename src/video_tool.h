#pragma once

#include "http_transport.h"
#include "secret_store.h"

#include <QString>

/**
 * @brief Шаг видео сцены через Kling text-to-video.
 */
class CVideoTool {
 public:
   /**
    * @brief Создаёт инструмент видео.
    * @param transport - HTTP.
    * @param secrets - ключ Kling.
    */
   explicit CVideoTool(CHttpTransport* transport,
                       CSecretStore* secrets);

   /**
    * @brief Генерирует mp4 сцены во временный файл.
    * @param prompt - текст сцены и стиль.
    * @param duration_s - длительность 3..20.
    * @param error - текст ошибки.
    * @return путь файла или пусто.
    */
   QString run(const QString& prompt, int duration_s, QString& error);

 private:
   QString poll_video_url(const QString& task_id, QString& error);
   QString download_file(const QString& url, QString& error);
   bool wait_poll();

   CHttpTransport* transport_ = nullptr;
   CSecretStore* secrets_ = nullptr;
   bool cancelled_ = false;
};
