#pragma once

#include "http_transport.h"
#include "secret_store.h"

#include <QString>

/**
 * @brief Шаг 16:9 обложки через Kling Image.
 */
class CCoverTool {
 public:
   /**
    * @brief Создаёт инструмент обложки.
    * @param transport - HTTP.
    * @param secrets - ключ Kling.
    */
   explicit CCoverTool(CHttpTransport* transport,
                       CSecretStore* secrets);

   /**
    * @brief Пишет youtube_cover.jpg в папку ролика.
    * @param library_root - корень библиотеки.
    * @param short_id - ролик.
    * @param prompt - тема и стиль.
    * @param error - текст ошибки.
    * @return относительный путь или пусто.
    */
   QString run(const QString& library_root, const QString& short_id,
               const QString& prompt, QString& error);

 private:
   QString poll_image_url(const QString& task_id, QString& error);
   QString save_cover(const QByteArray& bytes,
                      const QString& library_root,
                      const QString& short_id, QString& error);
   bool wait_poll();

   CHttpTransport* transport_ = nullptr;
   CSecretStore* secrets_ = nullptr;
   bool cancelled_ = false;
};
