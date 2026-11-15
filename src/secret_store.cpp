#include "secret_store.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincrypt.h>

namespace {

QByteArray g_memory_blob;

}  // namespace

CSecretStore::CSecretStore(QObject* parent) : QObject(parent) {}

void CSecretStore::set_base_url(const QString& url) {
   const QString clean = url.trimmed();
   if (clean.isEmpty() || clean == base_url_) {
      return;
   }
   base_url_ = clean;
   emit settings_changed();
}

void CSecretStore::set_chat_model(const QString& model) {
   const QString clean = model.trimmed();
   if (clean.isEmpty() || clean == chat_model_) {
      return;
   }
   chat_model_ = clean;
   emit settings_changed();
}

void CSecretStore::set_tts_model(const QString& model) {
   const QString clean = model.trimmed();
   if (clean.isEmpty() || clean == tts_model_) {
      return;
   }
   tts_model_ = clean;
   emit settings_changed();
}

void CSecretStore::set_voice(const QString& voice) {
   const QString clean = voice.trimmed();
   if (clean.isEmpty() || clean == voice_) {
      return;
   }
   voice_ = clean;
   emit settings_changed();
}

void CSecretStore::set_api_key(const QString& key) {
   const QString clean = key.trimmed();
   if (clean.isEmpty()) {
      return;
   }
   api_key_ = clean;
   emit settings_changed();
}

void CSecretStore::set_kling_base_url(const QString& url) {
   const QString clean = url.trimmed();
   if (clean.isEmpty() || clean == kling_base_url_) {
      return;
   }
   kling_base_url_ = clean;
   emit settings_changed();
}

void CSecretStore::set_kling_model(const QString& model) {
   const QString clean = model.trimmed();
   if (clean.isEmpty() || clean == kling_model_) {
      return;
   }
   kling_model_ = clean;
   emit settings_changed();
}

void CSecretStore::set_kling_image_model(const QString& model) {
   const QString clean = model.trimmed();
   if (clean.isEmpty() || clean == kling_image_model_) {
      return;
   }
   kling_image_model_ = clean;
   emit settings_changed();
}

void CSecretStore::set_kling_api_key(const QString& key) {
   const QString clean = key.trimmed();
   if (clean.isEmpty()) {
      return;
   }
   kling_api_key_ = clean;
   emit settings_changed();
}

void CSecretStore::use_memory(bool enabled) {
   memory_ = enabled;
}

void CSecretStore::clear_memory() {
   g_memory_blob.clear();
}

QString CSecretStore::file_path() const {
   const QString root = QStandardPaths::writableLocation(
       QStandardPaths::AppLocalDataLocation);
   return QDir(root).filePath(QStringLiteral("secrets.bin"));
}

QByteArray CSecretStore::encode_blob() const {
   QJsonObject object;
   object.insert(QStringLiteral("base_url"), base_url_);
   object.insert(QStringLiteral("chat_model"), chat_model_);
   object.insert(QStringLiteral("tts_model"), tts_model_);
   object.insert(QStringLiteral("voice"), voice_);
   object.insert(QStringLiteral("api_key"), api_key_);
   object.insert(QStringLiteral("kling_base_url"), kling_base_url_);
   object.insert(QStringLiteral("kling_model"), kling_model_);
   object.insert(QStringLiteral("kling_image_model"),
                 kling_image_model_);
   object.insert(QStringLiteral("kling_api_key"), kling_api_key_);
   return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

bool CSecretStore::decode_blob(const QByteArray& blob) {
   const QJsonDocument document = QJsonDocument::fromJson(blob);
   if (!document.isObject()) {
      return false;
   }
   const QJsonObject object = document.object();
   const QString base =
       object.value(QStringLiteral("base_url")).toString();
   const QString chat =
       object.value(QStringLiteral("chat_model")).toString();
   const QString tts =
       object.value(QStringLiteral("tts_model")).toString();
   const QString voice =
       object.value(QStringLiteral("voice")).toString();
   if (!base.isEmpty()) {
      base_url_ = base;
   }
   if (!chat.isEmpty()) {
      chat_model_ = chat;
   }
   if (!tts.isEmpty()) {
      tts_model_ = tts;
   }
   if (!voice.isEmpty()) {
      voice_ = voice;
   }
   api_key_ = object.value(QStringLiteral("api_key")).toString();
   const QString kling_base =
       object.value(QStringLiteral("kling_base_url")).toString();
   const QString kling_model =
       object.value(QStringLiteral("kling_model")).toString();
   const QString kling_image =
       object.value(QStringLiteral("kling_image_model")).toString();
   if (!kling_base.isEmpty()) {
      kling_base_url_ = kling_base;
   }
   if (!kling_model.isEmpty()) {
      kling_model_ = kling_model;
   }
   if (!kling_image.isEmpty()) {
      kling_image_model_ = kling_image;
   }
   kling_api_key_ =
       object.value(QStringLiteral("kling_api_key")).toString();
   return true;
}

QByteArray CSecretStore::protect_blob(const QByteArray& plain) const {
   DATA_BLOB input;
   input.cbData = static_cast<DWORD>(plain.size());
   input.pbData = reinterpret_cast<BYTE*>(
       const_cast<char*>(plain.constData()));
   DATA_BLOB output{};
   if (!CryptProtectData(&input, L"YouTubeCreator", nullptr, nullptr,
                         nullptr, 0, &output)) {
      return {};
   }
   QByteArray blob(reinterpret_cast<char*>(output.pbData),
                   static_cast<int>(output.cbData));
   LocalFree(output.pbData);
   return blob;
}

QByteArray CSecretStore::unprotect_blob(
    const QByteArray& blob) const {
   DATA_BLOB input;
   input.cbData = static_cast<DWORD>(blob.size());
   input.pbData = reinterpret_cast<BYTE*>(
       const_cast<char*>(blob.constData()));
   DATA_BLOB output{};
   if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                           0, &output)) {
      return {};
   }
   QByteArray plain(reinterpret_cast<char*>(output.pbData),
                    static_cast<int>(output.cbData));
   LocalFree(output.pbData);
   return plain;
}

bool CSecretStore::load() {
   QByteArray blob;
   if (memory_) {
      blob = g_memory_blob;
   } else {
      QFile file(file_path());
      if (!file.exists()) {
         return true;
      }
      if (!file.open(QIODevice::ReadOnly)) {
         return false;
      }
      blob = unprotect_blob(file.readAll());
      if (blob.isEmpty()) {
         return false;
      }
   }
   if (blob.isEmpty()) {
      api_key_.clear();
      emit settings_changed();
      return true;
   }
   if (!decode_blob(blob)) {
      return false;
   }
   emit settings_changed();
   return true;
}

bool CSecretStore::save() {
   const QByteArray plain = encode_blob();
   if (memory_) {
      g_memory_blob = plain;
      emit settings_changed();
      return true;
   }
   const QByteArray blob = protect_blob(plain);
   if (blob.isEmpty()) {
      return false;
   }
   const QString path = file_path();
   QDir().mkpath(QFileInfo(path).absolutePath());
   QFile file(path);
   if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
      return false;
   }
   file.write(blob);
   emit settings_changed();
   return true;
}
