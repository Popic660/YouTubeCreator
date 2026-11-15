#pragma once

#include "channel_auth.h"
#include "http_transport.h"
#include "library_store.h"

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

/**
 * @brief Снимок статистики YouTube по каналу или видео.
 */
class CStatsSync : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(CLibraryStore* store READ store WRITE set_store
                  NOTIFY store_changed)
   Q_PROPERTY(CChannelAuth* auth READ auth WRITE set_auth
                  NOTIFY auth_changed)
   Q_PROPERTY(CHttpTransport* transport READ transport
                  WRITE set_transport NOTIFY transport_changed)
   Q_PROPERTY(QString lastError READ last_error NOTIFY finished)

 public:
   /**
    * @brief Создаёт синхронизатор.
    * @param parent - родитель Qt.
    */
   explicit CStatsSync(QObject* parent = nullptr);

   /**
    * @brief Хранилище снимков.
    * @return указатель или nullptr.
    */
   CLibraryStore* store() const;

   /**
    * @brief Задаёт хранилище.
    * @param store - библиотека.
    */
   void set_store(CLibraryStore* store);

   /**
    * @brief Каналы и access-токен.
    * @return указатель или nullptr.
    */
   CChannelAuth* auth() const;

   /**
    * @brief Задаёт авторизацию.
    * @param auth - каналы.
    */
   void set_auth(CChannelAuth* auth);

   /**
    * @brief HTTP к YouTube.
    * @return указатель или nullptr.
    */
   CHttpTransport* transport() const;

   /**
    * @brief Задаёт транспорт.
    * @param transport - HTTP.
    */
   void set_transport(CHttpTransport* transport);

   /**
    * @brief Последняя ошибка шага.
    * @return текст или пусто.
    */
   QString last_error() const;

   /**
    * @brief Тянет Data API и Analytics и пишет снимок.
    * @param kind - channel или video.
    * @param target_id - channel_id или video_id.
    * @return true, если снимок записан.
    */
   Q_INVOKABLE bool refresh(const QString& kind,
                            const QString& target_id);

 signals:
   /**
    * @brief Сменилось хранилище.
    */
   void store_changed();

   /**
    * @brief Сменилась авторизация.
    */
   void auth_changed();

   /**
    * @brief Сменился транспорт.
    */
   void transport_changed();

   /**
    * @brief Шаг синхронизации завершён.
    */
   void finished();

 private:
   QString channel_for_video(const QString& video_id) const;
   QString bearer(const QString& token) const;
   QJsonObject fetch_list(const QString& url,
                          const QString& token);
   QJsonObject fetch_report(const QString& channel_id,
                            const QString& video_id,
                            const QString& token);
   QJsonObject build_payload(const QString& kind,
                             const QJsonObject& list,
                             const QJsonObject& report) const;
   void set_error(const QString& text);

   CLibraryStore* store_ = nullptr;
   CChannelAuth* auth_ = nullptr;
   CHttpTransport* transport_ = nullptr;
   QString last_error_;
};
