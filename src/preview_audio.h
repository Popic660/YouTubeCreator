#pragma once

#include "project_document.h"

#include <QBuffer>
#include <QByteArray>
#include <QObject>
#include <QtQml/qqmlregistration.h>

class QAudioSink;

/**
 * @brief Смешивает дорожку A1 в PCM s16le stereo 44100.
 * @param document - проект.
 * @param from_ms - старт на таймлайне.
 * @param until_ms - конец на таймлайне.
 * @return байты PCM; тишина, если клипов нет.
 */
QByteArray mix_document_pcm(CProjectDocument* document, qint64 from_ms,
                            qint64 until_ms);

/**
 * @brief Звук превью, синхронный с play/pause документа.
 */
class CPreviewAudio : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(CProjectDocument* document READ document WRITE set_document
                  NOTIFY document_changed)

 public:
   /**
    * @brief Создаёт плеер.
    * @param parent - владелец.
    */
   explicit CPreviewAudio(QObject* parent = nullptr);

   /**
    * @brief Останавливает устройство.
    */
   ~CPreviewAudio() override;

   CProjectDocument* document() const { return document_; }

   /**
    * @brief Подключает документ.
    * @param document - проект.
    */
   void set_document(CProjectDocument* document);

 signals:
   void document_changed();

 private:
   void on_playing_changed();
   void start();
   void stop();

   CProjectDocument* document_ = nullptr;
   QAudioSink* sink_ = nullptr;
   QBuffer buffer_;
   QByteArray pcm_;
};
