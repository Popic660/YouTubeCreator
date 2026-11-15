#pragma once

#include "channel_auth.h"
#include "http_transport.h"
#include "library_store.h"

#include <QObject>
#include <QString>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

/**
 * @brief Публикация готового шортса на YouTube.
 */
class CPublisher : public QObject {
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
    * @brief Создаёт публикатор.
    * @param parent - родитель Qt.
    */
   explicit CPublisher(QObject* parent = nullptr);

   /**
    * @brief Хранилище роликов.
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
    * @brief Id публикации пары ролик+канал.
    * @param short_id - ролик.
    * @param channel_id - канал.
    * @return id строки или пусто.
    */
   Q_INVOKABLE QString publication_id(const QString& short_id,
                                      const QString& channel_id) const;

   /**
    * @brief Грузит ролик на выбранные каналы.
    * @param short_id - id ролика.
    * @param channel_ids - каналы.
    * @param title - заголовок до 100.
    * @param description - описание.
    * @param privacy - public / unlisted / private.
    * @return true, если хотя бы один канал опубликован.
    */
   Q_INVOKABLE bool publish(const QString& short_id,
                            const QStringList& channel_ids,
                            const QString& title,
                            const QString& description,
                            const QString& privacy);

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
    * @brief Шаг публикации завершён.
    */
   void finished();

 private:
   bool upload_channel(const QString& short_id,
                       const QString& channel_id,
                       const QString& title,
                       const QString& description,
                       const QString& privacy,
                       const QString& video_path,
                       const QString& thumb_path,
                       qint64 file_size);
   QByteArray snippet_body(const QString& title,
                           const QString& description,
                           const QString& privacy) const;
   QString bearer(const QString& token) const;
   QString response_text(const HttpResponse& response) const;
   void set_error(const QString& text);
   bool write_publication(const QString& short_id,
                          const QString& channel_id,
                          const QString& video_id,
                          const QString& privacy,
                          const QString& status,
                          const QString& cover_status,
                          const QString& error);
   bool is_thumbnail_skip(const HttpResponse& response) const;

   CLibraryStore* store_ = nullptr;
   CChannelAuth* auth_ = nullptr;
   CHttpTransport* transport_ = nullptr;
   QString last_error_;
};
