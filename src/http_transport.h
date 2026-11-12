#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <vector>

/**
 * @brief Ответ HTTP POST.
 */
struct HttpResponse {
   int status = 0;
   QByteArray body;
   QString error;
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
   Q_PROPERTY(QString lastUrl READ last_url NOTIFY log_changed)
   Q_PROPERTY(QString lastBody READ last_body_text NOTIFY log_changed)

 public:
   /**
    * @brief Создаёт живой транспорт.
    * @param parent - владелец.
    */
   explicit CHttpTransport(QObject* parent = nullptr);

   int call_count() const { return call_count_; }
   int chat_count() const { return chat_count_; }
   int speech_count() const { return speech_count_; }
   QString last_url() const { return last_url_; }
   QString last_body_text() const {
      return QString::fromUtf8(last_body_);
   }

   /**
    * @brief Переключает на очередь ответов без сети.
    */
   Q_INVOKABLE void use_stub();

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
    * @brief Сбрасывает очередь и счётчики.
    */
   Q_INVOKABLE void clear();

   /**
    * @brief Прерывает текущий POST.
    */
   Q_INVOKABLE void abort();

   /**
    * @brief Выполняет POST.
    * @param url - адрес.
    * @param bearer - ключ или пусто.
    * @param body - тело.
    * @return ответ или ошибка.
    */
   HttpResponse post(const QString& url, const QString& bearer,
                     const QByteArray& body);

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
   HttpResponse post_stub();
   HttpResponse post_live(const QString& url, const QString& bearer,
                          const QByteArray& body);
   void record(const QString& url, const QByteArray& body);

   bool stub_ = false;
   bool aborted_ = false;
   int call_count_ = 0;
   int chat_count_ = 0;
   int speech_count_ = 0;
   QString last_url_;
   QByteArray last_body_;
   std::vector<HttpResponse> queue_;
};
