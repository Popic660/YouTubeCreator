#pragma once

#include "http_transport.h"
#include "secret_store.h"

#include <QByteArray>
#include <QString>
#include <QStringList>

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
   /**
    * @brief POST одного куска текста в audio/speech.
    * @param text - реплика.
    * @param error - текст ошибки.
    * @return тело wav или пусто.
    */
   QByteArray request_chunk(const QString& text, QString& error);

   /**
    * @brief Пишет байты wav во временный файл.
    * @param body - содержимое.
    * @param error - текст ошибки.
    * @return путь или пусто.
    */
   QString write_wav(const QByteArray& body, QString& error) const;

   /**
    * @brief Склеивает wav одного формата.
    * @param paths - куски.
    * @param error - текст ошибки.
    * @return путь результата или пусто.
    */
   QString concat_wavs(const QStringList& paths,
                       QString& error) const;

   CHttpTransport* transport_ = nullptr;
   CSecretStore* secrets_ = nullptr;
};
