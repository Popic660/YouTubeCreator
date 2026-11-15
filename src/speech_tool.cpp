#include "speech_tool.h"

#include "scene_parser.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QThread>
#include <QUuid>
#include <QtEndian>

#include <algorithm>

namespace {

constexpr int kOrpheusMaxChars = 200;
constexpr int kOpenAiMaxChars = 4096;
constexpr int kOrpheusGapMs = 4500;
constexpr int kRateLimitTries = 6;

int max_input_chars(const QString& model) {
   const QString id = model.toLower();
   if (id.contains(QLatin1String("orpheus")) ||
       id.contains(QLatin1String("canopylabs"))) {
      return kOrpheusMaxChars;
   }
   return kOpenAiMaxChars;
}

QString spoken_from_scene(const Scene& scene) {
   const QString line = scene.line.trimmed();
   if (!line.isEmpty()) {
      return line;
   }
   return scene.prompt.trimmed();
}

QString narration_text(const QString& script) {
   const std::vector<Scene> scenes = parse_scenes(script);
   QStringList parts;
   for (const Scene& scene : scenes) {
      const QString spoken = spoken_from_scene(scene);
      if (!spoken.isEmpty()) {
         parts.append(spoken);
      }
   }
   return parts.join(QStringLiteral(". "));
}

QStringList split_chunks(const QString& text, int max_chars) {
   const QString clean = text.simplified();
   if (clean.isEmpty()) {
      return {};
   }
   if (clean.size() <= max_chars) {
      return {clean};
   }
   QStringList chunks;
   int index = 0;
   while (index < clean.size()) {
      int end = std::min(index + max_chars,
                         static_cast<int>(clean.size()));
      if (end < clean.size()) {
         const int space =
             clean.lastIndexOf(QLatin1Char(' '), end - 1);
         if (space > index) {
            end = space;
         }
      }
      const QString piece =
          clean.mid(index, end - index).trimmed();
      if (!piece.isEmpty()) {
         chunks.append(piece);
      }
      index = end;
      while (index < clean.size() && clean.at(index).isSpace()) {
         ++index;
      }
   }
   return chunks;
}

int rate_limit_wait_ms(const HttpResponse& response,
                       const QString& message) {
   const bool limited =
       response.status == 429 ||
       message.contains(QLatin1String("Rate limit"),
                        Qt::CaseInsensitive) ||
       message.contains(QLatin1String("try again in"),
                        Qt::CaseInsensitive);
   if (!limited) {
      return -1;
   }
   const QRegularExpression re(
       QStringLiteral("try again in ([0-9]+(?:\\.[0-9]+)?)s"),
       QRegularExpression::CaseInsensitiveOption);
   const QRegularExpressionMatch match = re.match(message);
   if (match.hasMatch()) {
      const double sec = match.captured(1).toDouble();
      return std::max(500, static_cast<int>(sec * 1000.0) + 250);
   }
   return 5000;
}

int data_chunk_offset(const QByteArray& wav) {
   if (wav.size() < 44 || !wav.startsWith("RIFF") ||
       wav.mid(8, 4) != "WAVE") {
      return -1;
   }
   int index = 12;
   while (index + 8 <= wav.size()) {
      const QByteArray id = wav.mid(index, 4);
      const auto size = qFromLittleEndian<quint32>(
          reinterpret_cast<const uchar*>(
              wav.constData() + index + 4));
      if (id == "data") {
         return index;
      }
      index += 8 + static_cast<int>(size);
      if ((size % 2) != 0) {
         ++index;
      }
   }
   return -1;
}

}  // namespace

CSpeechTool::CSpeechTool(CHttpTransport* transport,
                         CSecretStore* secrets)
    : transport_(transport), secrets_(secrets) {}

QByteArray CSpeechTool::request_chunk(const QString& text,
                                      QString& error) {
   QJsonObject payload;
   payload.insert(QStringLiteral("model"), secrets_->tts_model());
   payload.insert(QStringLiteral("input"), text);
   payload.insert(QStringLiteral("voice"), secrets_->voice());
   payload.insert(QStringLiteral("response_format"),
                  QStringLiteral("wav"));
   const QString url =
       secrets_->openai_url(QStringLiteral("audio/speech"));
   const QByteArray body =
       QJsonDocument(payload).toJson(QJsonDocument::Compact);
   for (int attempt = 0; attempt < kRateLimitTries; ++attempt) {
      const HttpResponse response = transport_->post(
          url, secrets_->secret_api_key(), body);
      if (!response.error.isEmpty()) {
         error = response.error;
         return {};
      }
      const QString api_error = http_api_message(response);
      const int wait_ms = rate_limit_wait_ms(response, api_error);
      if (wait_ms >= 0 && attempt + 1 < kRateLimitTries) {
         if (!transport_->is_stub()) {
            QThread::msleep(static_cast<unsigned long>(wait_ms));
         }
         continue;
      }
      if (response.status >= 400 ||
          response.body.trimmed().startsWith('{')) {
         error = api_error.isEmpty() ? QStringLiteral("empty speech")
                                     : api_error;
         return {};
      }
      if (response.body.isEmpty()) {
         error = QStringLiteral("empty speech");
         return {};
      }
      return response.body;
   }
   error = QStringLiteral("empty speech");
   return {};
}

QString CSpeechTool::write_wav(const QByteArray& body,
                               QString& error) const {
   const QString path = QDir::temp().filePath(
       QStringLiteral("yc-voice-") +
       QUuid::createUuid().toString(QUuid::WithoutBraces) +
       QStringLiteral(".wav"));
   QFile file(path);
   if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
      error = QStringLiteral("speech file");
      return {};
   }
   file.write(body);
   return path;
}

QString CSpeechTool::concat_wavs(const QStringList& paths,
                                 QString& error) const {
   if (paths.size() == 1) {
      return paths.at(0);
   }
   QByteArray first;
   QFile head(paths.at(0));
   if (!head.open(QIODevice::ReadOnly)) {
      error = QStringLiteral("speech file");
      return {};
   }
   first = head.readAll();
   const int first_data = data_chunk_offset(first);
   if (first_data < 0) {
      error = QStringLiteral("speech file");
      return {};
   }
   const int first_pcm = first_data + 8;
   QByteArray pcm = first.mid(first_pcm);
   const QByteArray fmt = first.mid(12, first_data - 12);
   for (int i = 1; i < paths.size(); ++i) {
      QFile next(paths.at(i));
      if (!next.open(QIODevice::ReadOnly)) {
         error = QStringLiteral("speech file");
         return {};
      }
      const QByteArray wav = next.readAll();
      const int data = data_chunk_offset(wav);
      if (data < 0 || wav.mid(12, data - 12) != fmt) {
         error = QStringLiteral("speech file");
         return {};
      }
      pcm += wav.mid(data + 8);
   }
   QByteArray out = first.left(first_pcm);
   const quint32 pcm_size = static_cast<quint32>(pcm.size());
   qToLittleEndian(pcm_size, out.data() + first_data + 4);
   const quint32 riff_size = static_cast<quint32>(out.size() +
                                                  pcm.size() - 8);
   qToLittleEndian(riff_size, out.data() + 4);
   out += pcm;
   return write_wav(out, error);
}

QString CSpeechTool::run(const QString& script, QString& error) {
   error.clear();
   if (transport_ == nullptr || secrets_ == nullptr) {
      error = QStringLiteral("no transport");
      return {};
   }
   const QString spoken = narration_text(script);
   const QStringList chunks =
       split_chunks(spoken, max_input_chars(secrets_->tts_model()));
   if (chunks.isEmpty()) {
      error = QStringLiteral("empty speech");
      return {};
   }
   QStringList paths;
   const bool orpheus =
       max_input_chars(secrets_->tts_model()) == kOrpheusMaxChars;
   for (int i = 0; i < chunks.size(); ++i) {
      if (orpheus && i > 0 && !transport_->is_stub()) {
         QThread::msleep(static_cast<unsigned long>(kOrpheusGapMs));
      }
      const QByteArray body = request_chunk(chunks.at(i), error);
      if (body.isEmpty()) {
         for (const QString& path : paths) {
            QFile::remove(path);
         }
         return {};
      }
      const QString path = write_wav(body, error);
      if (path.isEmpty()) {
         for (const QString& old : paths) {
            QFile::remove(old);
         }
         return {};
      }
      paths.append(path);
   }
   QString joined = concat_wavs(paths, error);
   if (joined.isEmpty()) {
      for (const QString& path : paths) {
         QFile::remove(path);
      }
      return {};
   }
   for (const QString& path : paths) {
      if (path != joined) {
         QFile::remove(path);
      }
   }
   return joined;
}
