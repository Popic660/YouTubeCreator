#include "exporter.h"

#include "ffmpeg_api.h"
#include "preview_audio.h"

#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QSize>

#include <algorithm>
#include <cstdint>

namespace {

constexpr int kFps = 30;

constexpr int kAacRate = 44100;

/**
 * @brief Закрывает кодеки и контейнер.
 * @param video - видеокодек.
 * @param audio - аудиокодек.
 * @param format - контейнер.
 */
void close_streams(AVCodecContext* video, AVCodecContext* audio,
                   AVFormatContext* format) {
   if (video != nullptr) {
      avcodec_free_context(&video);
   }
   if (audio != nullptr) {
      avcodec_free_context(&audio);
   }
   if (format != nullptr) {
      if (!(format->oformat->flags & AVFMT_NOFILE) &&
          format->pb != nullptr) {
         avio_closep(&format->pb);
      }
      avformat_free_context(format);
   }
}

/**
 * @brief Открывает AAC-кодек и поток.
 * @param format - контейнер.
 * @param stream - созданный поток.
 * @return контекст или nullptr.
 */
AVCodecContext* open_aac(AVFormatContext* format, AVStream** stream) {
   const AVCodec* codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
   if (codec == nullptr || stream == nullptr) {
      return nullptr;
   }
   *stream = avformat_new_stream(format, nullptr);
   AVCodecContext* ctx = avcodec_alloc_context3(codec);
   if (*stream == nullptr || ctx == nullptr) {
      avcodec_free_context(&ctx);
      return nullptr;
   }
   av_channel_layout_default(&ctx->ch_layout, 2);
   ctx->sample_rate = kAacRate;
   ctx->sample_fmt = AV_SAMPLE_FMT_FLTP;
   ctx->bit_rate = 128000;
   ctx->time_base = {1, kAacRate};
   if (format->oformat->flags & AVFMT_GLOBALHEADER) {
      ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
   }
   if (avcodec_open2(ctx, codec, nullptr) < 0) {
      avcodec_free_context(&ctx);
      return nullptr;
   }
   if (avcodec_parameters_from_context((*stream)->codecpar, ctx) <
       0) {
      avcodec_free_context(&ctx);
      return nullptr;
   }
   (*stream)->time_base = ctx->time_base;
   return ctx;
}

}  // namespace

CExporter::CExporter(QObject* parent) : QObject(parent) {}

void CExporter::set_document(CProjectDocument* document) {
   if (document_ == document) {
      return;
   }
   document_ = document;
   emit document_changed();
}

void CExporter::set_compositor(CFrameCompositor* compositor) {
   if (compositor_ == compositor) {
      return;
   }
   compositor_ = compositor;
   emit compositor_changed();
}

QString CExporter::export_current() {
   last_path_.clear();
   last_error_.clear();
   last_width_ = 0;
   last_height_ = 0;
   if (document_ == nullptr || compositor_ == nullptr ||
       !document_->has_clips() || document_->store() == nullptr) {
      last_error_ = QStringLiteral(
          "Нет клипов для экспорта. Выберите ролик с видео в дереве "
          "слева: папка → «⋯» → «Импорт видео», затем нажмите "
          "«Экспорт».");
      emit finished();
      return {};
   }
   const qint64 duration = std::max<qint64>(document_->duration_ms(), 1);
   const QString rel =
       "exports/" + document_->short_id() + ".mp4";
   const QString path =
       QDir(document_->store()->root_path()).filePath(rel);
   QDir().mkpath(QFileInfo(path).absolutePath());

   const AVCodec* codec = avcodec_find_encoder(AV_CODEC_ID_H264);
   if (codec == nullptr) {
      codec = avcodec_find_encoder_by_name("libx264");
   }
   if (codec == nullptr) {
      last_error_ = QStringLiteral("Не найден кодировщик H.264.");
      emit finished();
      return {};
   }

   AVFormatContext* format = nullptr;
   const QByteArray utf8 = path.toUtf8();
   if (avformat_alloc_output_context2(&format, nullptr, "mp4",
                                      utf8.constData()) < 0) {
      emit finished();
      return {};
   }
   AVStream* stream = avformat_new_stream(format, nullptr);
   AVCodecContext* ctx = avcodec_alloc_context3(codec);
   if (stream == nullptr || ctx == nullptr) {
      close_streams(ctx, nullptr, format);
      emit finished();
      return {};
   }
   ctx->codec_id = codec->id;
   ctx->width = CFrameCompositor::kExportWidth;
   ctx->height = CFrameCompositor::kExportHeight;
   ctx->pix_fmt = AV_PIX_FMT_YUV420P;
   ctx->time_base = {1, kFps};
   ctx->framerate = {kFps, 1};
   ctx->gop_size = kFps;
   ctx->max_b_frames = 0;
   if (format->oformat->flags & AVFMT_GLOBALHEADER) {
      ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
   }
   if (avcodec_open2(ctx, codec, nullptr) < 0) {
      close_streams(ctx, nullptr, format);
      emit finished();
      return {};
   }
   if (avcodec_parameters_from_context(stream->codecpar, ctx) < 0) {
      close_streams(ctx, nullptr, format);
      emit finished();
      return {};
   }
   stream->time_base = ctx->time_base;
   AVStream* audio_stream = nullptr;
   AVCodecContext* audio_ctx = open_aac(format, &audio_stream);
   if (!(format->oformat->flags & AVFMT_NOFILE)) {
      if (avio_open(&format->pb, utf8.constData(), AVIO_FLAG_WRITE) <
          0) {
         close_streams(ctx, audio_ctx, format);
         emit finished();
         return {};
      }
   }
   if (avformat_write_header(format, nullptr) < 0) {
      close_streams(ctx, audio_ctx, format);
      emit finished();
      return {};
   }

   SwsContext* sws = sws_getContext(
       ctx->width, ctx->height, AV_PIX_FMT_BGRA, ctx->width,
       ctx->height, AV_PIX_FMT_YUV420P, SWS_BILINEAR, nullptr,
       nullptr, nullptr);
   AVFrame* frame = av_frame_alloc();
   frame->format = AV_PIX_FMT_YUV420P;
   frame->width = ctx->width;
   frame->height = ctx->height;
   av_frame_get_buffer(frame, 32);
   AVPacket* packet = av_packet_alloc();

   const int total = static_cast<int>((duration * kFps + 999) / 1000);
   bool ok = true;
   for (int i = 0; i < total && ok; ++i) {
      const qint64 time_ms = static_cast<qint64>(i) * 1000 / kFps;
      QImage image = compositor_->compose_export(time_ms)
                         .convertToFormat(QImage::Format_ARGB32);
      if (image.size() != QSize(ctx->width, ctx->height)) {
         image = image.scaled(ctx->width, ctx->height,
                              Qt::IgnoreAspectRatio,
                              Qt::SmoothTransformation);
      }
      const uint8_t* src[1] = {image.constBits()};
      int src_linesize[1] = {static_cast<int>(image.bytesPerLine())};
      sws_scale(sws, src, src_linesize, 0, ctx->height, frame->data,
                frame->linesize);
      frame->pts = i;
      if (avcodec_send_frame(ctx, frame) < 0) {
         ok = false;
         break;
      }
      while (avcodec_receive_packet(ctx, packet) == 0) {
         av_packet_rescale_ts(packet, ctx->time_base, stream->time_base);
         packet->stream_index = stream->index;
         if (av_interleaved_write_frame(format, packet) < 0) {
            ok = false;
         }
         av_packet_unref(packet);
      }
   }
   avcodec_send_frame(ctx, nullptr);
   while (ok && avcodec_receive_packet(ctx, packet) == 0) {
      av_packet_rescale_ts(packet, ctx->time_base, stream->time_base);
      packet->stream_index = stream->index;
      av_interleaved_write_frame(format, packet);
      av_packet_unref(packet);
   }
   if (ok && audio_ctx != nullptr && audio_stream != nullptr) {
      AVFrame* audio = av_frame_alloc();
      audio->format = audio_ctx->sample_fmt;
      audio->ch_layout = audio_ctx->ch_layout;
      audio->sample_rate = audio_ctx->sample_rate;
      audio->nb_samples = audio_ctx->frame_size > 0
                              ? audio_ctx->frame_size
                              : 1024;
      av_frame_get_buffer(audio, 0);
      const int64_t total_samples =
          duration * kAacRate / 1000;
      const QByteArray pcm = mix_document_pcm(document_, 0, duration);
      const auto* samples =
          reinterpret_cast<const int16_t*>(pcm.constData());
      const int pcm_values = pcm.size() / 2;
      int pcm_index = 0;
      int64_t pts = 0;
      while (pts < total_samples) {
         av_frame_make_writable(audio);
         auto* left_plane =
             reinterpret_cast<float*>(audio->extended_data[0]);
         auto* right_plane =
             reinterpret_cast<float*>(audio->extended_data[1]);
         for (int s = 0; s < audio->nb_samples; ++s) {
            float left = 0;
            float right = 0;
            if (pcm_index + 1 < pcm_values) {
               left = samples[pcm_index] / 32768.0f;
               right = samples[pcm_index + 1] / 32768.0f;
               pcm_index += 2;
            }
            left_plane[s] = left;
            right_plane[s] = right;
         }
         audio->pts = pts;
         pts += audio->nb_samples;
         if (avcodec_send_frame(audio_ctx, audio) < 0) {
            ok = false;
            break;
         }
         while (avcodec_receive_packet(audio_ctx, packet) == 0) {
            av_packet_rescale_ts(packet, audio_ctx->time_base,
                                 audio_stream->time_base);
            packet->stream_index = audio_stream->index;
            av_interleaved_write_frame(format, packet);
            av_packet_unref(packet);
         }
      }
      avcodec_send_frame(audio_ctx, nullptr);
      while (avcodec_receive_packet(audio_ctx, packet) == 0) {
         av_packet_rescale_ts(packet, audio_ctx->time_base,
                              audio_stream->time_base);
         packet->stream_index = audio_stream->index;
         av_interleaved_write_frame(format, packet);
         av_packet_unref(packet);
      }
      av_frame_free(&audio);
   }
   av_write_trailer(format);
   av_packet_free(&packet);
   av_frame_free(&frame);
   sws_freeContext(sws);
   close_streams(ctx, audio_ctx, format);

   if (!ok || !QFileInfo::exists(path)) {
      emit finished();
      return {};
   }
   last_path_ = path;
   last_width_ = CFrameCompositor::kExportWidth;
   last_height_ = CFrameCompositor::kExportHeight;
   emit finished();
   return path;
}
