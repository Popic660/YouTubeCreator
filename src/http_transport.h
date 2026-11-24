#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <vector>

/**
 * @brief Ответ HTTP POST.
 */
struct HttpResponse {
   int status = 0;
   QByteArray body;
   QString error;
   QString location;
};

/**
 * @brief Текст ошибки из JSON тела OpenAI-совместимого ответа.
 * @param response - ответ POST.
 * @return сообщение API или пусто.
 */
QString http_api_message(const HttpResponse& response);

/**
 * @brief POST для инструментов модели: заглушка или живая сеть.
 */
class CHttpTransport : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(int callCount READ call_count NOTIFY log_changed)
   Q_PROPERTY(int chatCount READ chat_count NOTIFY log_changed)
   Q_PROPERTY(int speechCount READ speech_count NOTIFY log_changed)
   Q_PROPERTY(int klingCount READ kling_count NOTIFY log_changed)
   Q_PROPERTY(int googleCount READ google_count NOTIFY log_changed)
   Q_PROPERTY(QString lastUrl READ last_url NOTIFY log_changed)
   Q_PROPERTY(QString lastBody READ last_body_text NOTIFY log_changed)
   Q_PROPERTY(QStringList urls READ urls NOTIFY log_changed)
   Q_PROPERTY(QString lastLocation READ last_location
                  NOTIFY log_changed)

 public:
   /**
    * @brief Создаёт живой транспорт.
    * @param parent - владелец.
    */
   explicit CHttpTransport(QObject* parent = nullptr);

   int call_count() const { return call_count_; }
   int chat_count() const { return chat_count_; }
   int speech_count() const { return speech_count_; }
   int kling_count() const { return kling_count_; }
   int google_count() const { return google_count_; }
   QString last_url() const { return last_url_; }
   QStringList urls() const { return urls_; }
   QString last_location() const { return last_location_; }
   QString last_body_text() const {
      return QString::fromUtf8(last_body_);
   }

   /**
    * @brief Переключает на очередь ответов без сети.
    */
   Q_INVOKABLE void use_stub();

   /**
    * @brief Сообщает, что ответы из очереди, без сети.
    * @return true, если заглушка.
    */
   bool is_stub() const { return stub_; }

   /**
    * @brief Кладёт JSON-ответ в очередь заглушки.
    * @param json - тело ответа.
    */
   Q_INVOKABLE void enqueue_json(const QString& json);

   /**
    * @brief Кладёт байты файла в очередь заглушки.
    * @param path - путь файла.
    */
   Q_INVOKABLE void enqueue_file(const QString& path);

   /**
    * @brief Кладёт ошибку в очередь заглушки.
    * @param error - текст ошибки.
    */
   Q_INVOKABLE void enqueue_error(const QString& error);

   /**
    * @brief Заголовок для следующего ответа заглушки.
    * @param name - имя, например Location.
    * @param value - значение.
    */
   Q_INVOKABLE void enqueue_header(const QString& name,
                                   const QString& value);

   /**
    * @brief HTTP-статус для следующего ответа заглушки.
    * @param status - код, например 403.
    */
   Q_INVOKABLE void enqueue_status(int status);

   /**
    * @brief Сбрасывает очередь и счётчики.
    */
   Q_INVOKABLE void clear();

   /**
    * @brief Прерывает текущий POST или GET.
    */
   Q_INVOKABLE void abort();

   /**
    * @brief Снимает флаг отмены перед новым запуском.
    */
   void clear_abort();

   /**
    * @brief Выполняет POST.
    * @param url - адрес.
    * @param bearer - ключ или пусто.
    * @param body - тело.
    * @param content_type - тип тела или пусто для JSON.
    * @return ответ или ошибка.
    */
   HttpResponse post(const QString& url, const QString& bearer,
                     const QByteArray& body,
                     const QString& content_type = QString(),
                     const QVariantMap& headers = QVariantMap());

   /**
    * @brief Выполняет PUT.
    * @param url - адрес.
    * @param bearer - ключ или пусто.
    * @param body - тело.
    * @param content_type - тип тела или пусто.
    * @param headers - сырые заголовки.
    * @return ответ или ошибка.
    */
   HttpResponse put(const QString& url, const QString& bearer,
                    const QByteArray& body,
                    const QString& content_type = QString(),
                    const QVariantMap& headers = QVariantMap());

   /**
    * @brief POST для QML-тестов.
    * @param url - адрес.
    * @param bearer - ключ или пусто.
    * @param body - тело.
    * @param content_type - тип или пусто для JSON.
    * @return status, body, error.
    */
   Q_INVOKABLE QVariantMap post(const QString& url,
                                const QString& bearer,
                                const QString& body,
                                const QString& content_type);

   /**
    * @brief Выполняет GET.
    * @param url - адрес.
    * @param bearer - ключ или пусто.
    * @return ответ или ошибка.
    */
   HttpResponse get_response(const QString& url,
                             const QString& bearer);

   /**
    * @brief GET для QML-тестов.
    * @param url - адрес.
    * @param bearer - ключ или пусто.
    * @return status, body, error.
    */
   Q_INVOKABLE QVariantMap get(const QString& url,
                               const QString& bearer);

   /**
    * @brief PUT для QML-тестов.
    * @param url - адрес.
    * @param bearer - ключ или пусто.
    * @param body - тело.
    * @param content_type - тип или пусто.
    * @return status, body, error, location.
    */
   Q_INVOKABLE QVariantMap put(const QString& url,
                               const QString& bearer,
                               const QString& body,
                               const QString& content_type);

 signals:
   /**
    * @brief Журнал запросов изменился.
    */
   void log_changed();

   /**
    * @brief Нужно оборвать живой ответ.
    */
   void abort_requested();

 private:
   HttpResponse take_stub();
   HttpResponse live(const QString& method, const QString& url,
                     const QString& bearer, const QByteArray& body,
                     const QString& content_type,
                     const QVariantMap& headers);
   void apply_pending_headers(HttpResponse* response);
   void record(const QString& url, const QByteArray& body);
   static QVariantMap to_map(const HttpResponse& response);

   bool stub_ = false;
   bool aborted_ = false;
   int call_count_ = 0;
   int chat_count_ = 0;
   int speech_count_ = 0;
   int kling_count_ = 0;
   int google_count_ = 0;
   QString last_url_;
   QString last_location_;
   QByteArray last_body_;
   QStringList urls_;
   QString pending_location_;
   int pending_status_ = 0;
   std::vector<HttpResponse> queue_;
};
