#include "preview_audio.h"

#include "media_io.h"

#include <QAudioDevice>
#include <QAudioFormat>
#include <QAudioSink>
#include <QGuiApplication>
#include <QIODevice>
#include <QMediaDevices>

#include <algorithm>
#include <cstdint>
#include <vector>

namespace {

constexpr int kRate = 44100;

}  // namespace

QByteArray mix_document_pcm(CProjectDocument* document, qint64 from_ms,
                            qint64 until_ms) {
   if (document == nullptr || until_ms <= from_ms) {
      return {};
   }
   const int frames =
       static_cast<int>((until_ms - from_ms) * kRate / 1000);
   if (frames <= 0) {
      return {};
   }
   std::vector<int32_t> acc(static_cast<std::size_t>(frames) * 2u, 0);
   const int count = document->item_count();
   for (int i = 0; i < count; ++i) {
      const QString id = document->clip_id_at(i);
      if (document->clip_track(id) != QLatin1String("a1")) {
         continue;
      }
      const qint64 start = document->clip_start(id);
      const qint64 in_ms = document->clip_in(id);
      const qint64 out_ms = document->clip_out(id);
      const qint64 clip_end = start + (out_ms - in_ms);
      const qint64 ov_start = std::max(from_ms, start);
      const qint64 ov_end = std::min(until_ms, clip_end);
      if (ov_end <= ov_start) {
         continue;
      }
      const qint64 src_in = in_ms + (ov_start - start);
      const qint64 src_out = in_ms + (ov_end - start);
      const QByteArray part = CMediaIo::decode_pcm(
          document->clip_abs_path(id), src_in, src_out,
          document->clip_volume(id));
      const int dst_off =
          static_cast<int>((ov_start - from_ms) * kRate / 1000);
      const auto* src =
          reinterpret_cast<const int16_t*>(part.constData());
      const int src_frames = part.size() / 4;
      for (int s = 0; s < src_frames; ++s) {
         const int di = dst_off + s;
         if (di < 0 || di >= frames) {
            continue;
         }
         acc[static_cast<std::size_t>(di) * 2u] += src[s * 2];
         acc[static_cast<std::size_t>(di) * 2u + 1u] += src[s * 2 + 1];
      }
   }
   QByteArray pcm(frames * 4, '\0');
   auto* out = reinterpret_cast<int16_t*>(pcm.data());
   for (int s = 0; s < frames * 2; ++s) {
      int32_t value = acc[static_cast<std::size_t>(s)];
      if (value > 32767) {
         value = 32767;
      } else if (value < -32768) {
         value = -32768;
      }
      out[s] = static_cast<int16_t>(value);
   }
   return pcm;
}

CPreviewAudio::CPreviewAudio(QObject* parent) : QObject(parent) {}

CPreviewAudio::~CPreviewAudio() {
   stop();
}

void CPreviewAudio::set_document(CProjectDocument* document) {
   if (document_ == document) {
      return;
   }
   if (document_ != nullptr) {
      disconnect(document_, nullptr, this, nullptr);
   }
   stop();
   document_ = document;
   if (document_ != nullptr) {
      connect(document_, &CProjectDocument::playing_changed, this,
              &CPreviewAudio::on_playing_changed);
   }
   emit document_changed();
}

void CPreviewAudio::on_playing_changed() {
   if (document_ != nullptr && document_->is_playing()) {
      start();
   } else {
      stop();
   }
}

void CPreviewAudio::start() {
   stop();
   if (document_ == nullptr) {
      return;
   }
   if (QGuiApplication::platformName() == QLatin1String("offscreen")) {
      return;
   }
   pcm_ = mix_document_pcm(document_, document_->playhead_ms(),
                           document_->duration_ms());
   if (pcm_.isEmpty()) {
      return;
   }
   QAudioFormat format;
   format.setSampleRate(kRate);
   format.setChannelCount(2);
   format.setSampleFormat(QAudioFormat::Int16);
   const QAudioDevice device = QMediaDevices::defaultAudioOutput();
   if (device.isNull()) {
      pcm_.clear();
      return;
   }
   sink_ = new QAudioSink(device, format, this);
   buffer_.close();
   buffer_.setData(pcm_);
   buffer_.open(QIODevice::ReadOnly);
   sink_->start(&buffer_);
}

void CPreviewAudio::stop() {
   if (sink_ != nullptr) {
      sink_->stop();
      delete sink_;
      sink_ = nullptr;
   }
   if (buffer_.isOpen()) {
      buffer_.close();
   }
   pcm_.clear();
}
