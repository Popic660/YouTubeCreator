#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

/**
 * @brief Ключ и модели чата и TTS вне sqlite.
 */
class CSecretStore : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(QString baseUrl READ base_url WRITE set_base_url
                  NOTIFY settings_changed)
   Q_PROPERTY(QString chatModel READ chat_model WRITE set_chat_model
                  NOTIFY settings_changed)
   Q_PROPERTY(QString ttsModel READ tts_model WRITE set_tts_model
                  NOTIFY settings_changed)
   Q_PROPERTY(QString voice READ voice WRITE set_voice
                  NOTIFY settings_changed)
   Q_PROPERTY(QString apiKey READ api_key_display WRITE set_api_key
                  NOTIFY settings_changed)
   Q_PROPERTY(bool hasKey READ has_key NOTIFY settings_changed)

 public:
   /**
    * @brief Создаёт пустое хранилище настроек.
    * @param parent - владелец.
    */
   explicit CSecretStore(QObject* parent = nullptr);

   QString base_url() const { return base_url_; }
   QString chat_model() const { return chat_model_; }
   QString tts_model() const { return tts_model_; }
   QString voice() const { return voice_; }

   /**
    * @brief Поле ключа для UI: после save всегда пустое.
    * @return пустая строка.
    */
   QString api_key_display() const { return {}; }

   /**
    * @brief Секрет для вызова модели.
    * @return ключ или пусто.
    */
   QString secret_api_key() const { return api_key_; }

   /**
    * @brief Сообщает, что ключ задан.
    * @return true, если ключ непустой.
    */
   bool has_key() const { return !api_key_.isEmpty(); }

   /**
    * @brief Задаёт адрес OpenAI-совместимого API.
    * @param url - базовый URL.
    */
   void set_base_url(const QString& url);

   /**
    * @brief Задаёт модель чата.
    * @param model - имя модели.
    */
   void set_chat_model(const QString& model);

   /**
    * @brief Задаёт модель речи.
    * @param model - имя модели.
    */
   void set_tts_model(const QString& model);

   /**
    * @brief Задаёт голос TTS.
    * @param voice - имя голоса.
    */
   void set_voice(const QString& voice);

   /**
    * @brief Задаёт ключ до save.
    * @param key - секрет.
    */
   void set_api_key(const QString& key);

   /**
    * @brief Включает память вместо DPAPI для тестов.
    * @param enabled - true для памяти.
    */
   Q_INVOKABLE void use_memory(bool enabled);

   /**
    * @brief Очищает общий блоб памяти.
    */
   Q_INVOKABLE void clear_memory();

   /**
    * @brief Читает сохранённые настройки.
    * @return true, если удалось прочитать или файла ещё нет.
    */
   Q_INVOKABLE bool load();

   /**
    * @brief Пишет настройки.
    * @return true, если записано.
    */
   Q_INVOKABLE bool save();

 signals:
   /**
    * @brief Настройки изменились.
    */
   void settings_changed();

 private:
   QString file_path() const;
   QByteArray encode_blob() const;
   bool decode_blob(const QByteArray& blob);
   QByteArray protect_blob(const QByteArray& plain) const;
   QByteArray unprotect_blob(const QByteArray& blob) const;

   QString base_url_ = QStringLiteral("https://api.openai.com");
   QString chat_model_ = QStringLiteral("gpt-4o-mini");
   QString tts_model_ = QStringLiteral("tts-1");
   QString voice_ = QStringLiteral("alloy");
   QString api_key_;
   bool memory_ = false;
};
