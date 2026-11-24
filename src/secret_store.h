#pragma once

#include <QHash>
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
   Q_PROPERTY(QString apiKeyHint READ api_key_hint
                  NOTIFY settings_changed)
   Q_PROPERTY(bool hasKey READ has_key NOTIFY settings_changed)
   Q_PROPERTY(bool hasGroqKey READ has_groq_key
                  NOTIFY settings_changed)
   Q_PROPERTY(QString klingBaseUrl READ kling_base_url
                  WRITE set_kling_base_url NOTIFY settings_changed)
   Q_PROPERTY(QString klingModel READ kling_model
                  WRITE set_kling_model NOTIFY settings_changed)
   Q_PROPERTY(QString klingImageModel READ kling_image_model
                  WRITE set_kling_image_model
                  NOTIFY settings_changed)
   Q_PROPERTY(QString klingApiKey READ kling_api_key_display
                  WRITE set_kling_api_key NOTIFY settings_changed)
   Q_PROPERTY(bool hasKlingKey READ has_kling_key
                  NOTIFY settings_changed)
   Q_PROPERTY(QString googleClientId READ google_client_id
                  WRITE set_google_client_id
                  NOTIFY settings_changed)
   Q_PROPERTY(QString googleClientSecret
                  READ google_client_secret_display
                  WRITE set_google_client_secret
                  NOTIFY settings_changed)
   Q_PROPERTY(bool hasGoogleClient READ has_google_client
                  NOTIFY settings_changed)
   Q_PROPERTY(bool hasGoogleSecret READ has_google_secret
                  NOTIFY settings_changed)

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
   QString kling_base_url() const { return kling_base_url_; }
   QString kling_model() const { return kling_model_; }
   QString kling_image_model() const { return kling_image_model_; }

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
    * @brief Собирает OpenAI-совместимый URL без второго /v1.
    * @param suffix - хвост вроде chat/completions.
    * @return полный URL.
    */
   Q_INVOKABLE QString openai_url(const QString& suffix) const;

   /**
    * @brief Сообщает, что ключ задан.
    * @return true, если ключ непустой.
    */
   bool has_key() const { return !api_key_.isEmpty(); }

   /**
    * @brief Маска сохранённого ключа для диалога настроек.
    * @return префикс и хвост или пусто.
    */
   QString api_key_hint() const;

   /**
    * @brief Сообщает, что сохранён ключ Groq.
    * @return true, если ключ начинается с gsk_.
    */
   bool has_groq_key() const;

   /**
    * @brief Поле ключа Kling для UI: после save всегда пустое.
    * @return пустая строка.
    */
   QString kling_api_key_display() const { return {}; }

   /**
    * @brief Секрет Kling для вызова модели.
    * @return ключ или пусто.
    */
   QString secret_kling_api_key() const { return kling_api_key_; }

   /**
    * @brief Сообщает, что ключ Kling задан.
    * @return true, если ключ непустой.
    */
   bool has_kling_key() const { return !kling_api_key_.isEmpty(); }

   QString google_client_id() const { return google_client_id_; }

   /**
    * @brief Поле секрета Google для UI: после save всегда пустое.
    * @return пустая строка.
    */
   QString google_client_secret_display() const { return {}; }

   /**
    * @brief Секрет OAuth-клиента Google.
    * @return секрет или пусто.
    */
   QString secret_google_client_secret() const {
      return google_client_secret_;
   }

   /**
    * @brief Сообщает, что client id Google задан.
    * @return true, если id непустой.
    */
   bool has_google_client() const {
      return !google_client_id_.isEmpty();
   }

   /**
    * @brief Сообщает, что секрет клиента Google задан.
    * @return true, если секрет непустой.
    */
   bool has_google_secret() const {
      return !google_client_secret_.isEmpty();
   }

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
    * @brief Задаёт адрес Kling.
    * @param url - базовый URL.
    */
   void set_kling_base_url(const QString& url);

   /**
    * @brief Задаёт модель видео Kling.
    * @param model - имя модели.
    */
   void set_kling_model(const QString& model);

   /**
    * @brief Задаёт модель картинки Kling.
    * @param model - имя модели.
    */
   void set_kling_image_model(const QString& model);

   /**
    * @brief Задаёт ключ Kling до save.
    * @param key - секрет.
    */
   void set_kling_api_key(const QString& key);

   /**
    * @brief Задаёт client id Google OAuth.
    * @param id - идентификатор клиента.
    */
   void set_google_client_id(const QString& id);

   /**
    * @brief Задаёт секрет клиента Google до save.
    * @param secret - секрет.
    */
   void set_google_client_secret(const QString& secret);

   /**
    * @brief Пишет refresh-токен канала.
    * @param channel_id - id канала YouTube.
    * @param token - refresh-токен.
    */
   Q_INVOKABLE void set_channel_refresh(const QString& channel_id,
                                        const QString& token);

   /**
    * @brief Удаляет refresh-токен канала.
    * @param channel_id - id канала YouTube.
    */
   Q_INVOKABLE void clear_channel_refresh(const QString& channel_id);

   /**
    * @brief Refresh-токен канала.
    * @param channel_id - id канала YouTube.
    * @return токен или пусто.
    */
   Q_INVOKABLE QString channel_refresh(const QString& channel_id) const;

   /**
    * @brief Сообщает, что refresh-токен канала задан.
    * @param channel_id - id канала YouTube.
    * @return true, если токен непустой.
    */
   Q_INVOKABLE bool has_channel_refresh(
       const QString& channel_id) const;

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

   /**
    * @brief Если ключ Groq смотрит на OpenAI, ставит адрес Groq.
    * @return true, если адрес сменили.
    */
   bool align_groq_key_host();

   /**
    * @brief Корень chat/TTS с учётом ключа Groq.
    * @return базовый URL.
    */
   QString chat_root() const;
   QByteArray protect_blob(const QByteArray& plain) const;
   QByteArray unprotect_blob(const QByteArray& blob) const;

   QString base_url_ = QStringLiteral("https://api.openai.com");
   QString chat_model_ = QStringLiteral("gpt-4o-mini");
   QString tts_model_ = QStringLiteral("tts-1");
   QString voice_ = QStringLiteral("alloy");
   QString api_key_;
   QString kling_base_url_ =
       QStringLiteral("https://api-singapore.klingai.com");
   QString kling_model_ = QStringLiteral("kling-4.0-flash");
   QString kling_image_model_ = QStringLiteral("kling-v3");
   QString kling_api_key_;
   QString google_client_id_;
   QString google_client_secret_;
   QHash<QString, QString> channel_tokens_;
   bool memory_ = false;
};
