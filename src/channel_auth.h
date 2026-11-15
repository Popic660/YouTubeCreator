#pragma once

#include "http_transport.h"
#include "library_store.h"
#include "secret_store.h"

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class QTcpServer;
class QTcpSocket;

/**
 * @brief OAuth Google и список каналов без публикации.
 */
class CChannelAuth : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(CLibraryStore* store READ store WRITE set_store
                  NOTIFY bindings_changed)
   Q_PROPERTY(CSecretStore* secrets READ secrets WRITE set_secrets
                  NOTIFY bindings_changed)
   Q_PROPERTY(CHttpTransport* transport READ transport
                  WRITE set_transport NOTIFY bindings_changed)
   Q_PROPERTY(int browserOpenCount READ browser_open_count
                  NOTIFY log_changed)
   Q_PROPERTY(QString lastError READ last_error NOTIFY log_changed)

 public:
   /**
    * @brief Создаёт оркестратор входа.
    * @param parent - владелец.
    */
   explicit CChannelAuth(QObject* parent = nullptr);

   CLibraryStore* store() const { return store_; }
   CSecretStore* secrets() const { return secrets_; }
   CHttpTransport* transport() const { return transport_; }
   int browser_open_count() const { return browser_open_count_; }
   QString last_error() const { return last_error_; }

   /**
    * @brief Задаёт библиотеку.
    * @param store - хранилище.
    */
   void set_store(CLibraryStore* store);

   /**
    * @brief Задаёт секреты.
    * @param secrets - DPAPI-хранилище.
    */
   void set_secrets(CSecretStore* secrets);

   /**
    * @brief Задаёт HTTP-транспорт.
    * @param transport - POST/GET.
    */
   void set_transport(CHttpTransport* transport);

   /**
    * @brief Включает заглушку без браузера.
    */
   Q_INVOKABLE void use_stub();

   /**
    * @brief Начинает вход: loopback и браузер, если не заглушка.
    */
   Q_INVOKABLE void start();

   /**
    * @brief Обменивает код на токены без браузера.
    * @param code - authorization code.
    * @return true, если канал записан.
    */
   Q_INVOKABLE bool complete_with_code(const QString& code);

   /**
    * @brief Отмена входа, список не меняется.
    */
   Q_INVOKABLE void complete_with_error();

   /**
    * @brief Отключает канал локально.
    * @param channel_id - id YouTube.
    * @return true, если запись снята.
    */
   Q_INVOKABLE bool disconnect_channel(const QString& channel_id);

   /**
    * @brief Число каналов в открытой библиотеке.
    * @return строки channels.
    */
   Q_INVOKABLE int channel_count() const;

   /**
    * @brief Id канала по индексу.
    * @param index - позиция с нуля.
    * @return channel_id или пусто.
    */
   Q_INVOKABLE QString channel_id_at(int index) const;

   /**
    * @brief Название канала по индексу.
    * @param index - позиция с нуля.
    * @return название или пусто.
    */
   Q_INVOKABLE QString channel_title_at(int index) const;

 signals:
   /**
    * @brief Привязки store/secrets/transport изменились.
    */
   void bindings_changed();

   /**
    * @brief Журнал входа изменился.
    */
   void log_changed();

 private:
   bool exchange_code(const QString& code);
   QByteArray token_body(const QString& code) const;
   QString auth_url() const;
   bool start_loopback();
   void stop_loopback();
   void on_connection();
   void reply_html(QTcpSocket* socket, const QString& body);
   static QString pkce_verifier();
   static QString pkce_challenge(const QString& verifier);

   CLibraryStore* store_ = nullptr;
   CSecretStore* secrets_ = nullptr;
   CHttpTransport* transport_ = nullptr;
   QTcpServer* server_ = nullptr;
   bool stub_ = false;
   int browser_open_count_ = 0;
   QString last_error_;
   QString verifier_;
   QString redirect_uri_;
};
