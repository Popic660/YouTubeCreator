#include "media_io.h"

#include "ffmpeg_api.h"

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QFileInfo>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace {

/**
 * @brief Открывает контейнер.
 * @param path - локальный путь.
 * @return контекст или nullptr.
 */
AVFormatContext* open_input(const QString& path) {
   AVFormatContext* format = nullptr;
   const QByteArray utf8 = path.toUtf8();
   if (avformat_open_input(&format, utf8.constData(), nullptr,
                           nullptr) < 0) {
      return nullptr;
   }
   if (avformat_find_stream_info(format, nullptr) < 0) {
      avformat_close_input(&format);
      return nullptr;
   }
   return format;
}

/**
 * @brief Ищет поток заданного типа.
 * @param format - контейнер.
 * @param type - видео или звук.
 * @return индекс или -1.
 */
int find_stream(AVFormatContext* format, AVMediaType type) {
   for (unsigned i = 0; i < format->nb_streams; ++i) {
      if (format->streams[i]->codecpar->codec_type == type) {
         return static_cast<int>(i);
      }
   }
   return -1;
}

/**
 * @brief Длительность контейнера в миллисекундах.
 * @param format - контейнер.
 * @return длительность.
 */
qint64 duration_ms_of(AVFormatContext* format) {
   if (format->duration > 0) {
      return format->duration / 1000;
   }
   for (unsigned i = 0; i < format->nb_streams; ++i) {
      const AVStream* stream = format->streams[i];
      if (stream->duration <= 0) {
         continue;
      }
      return av_rescale_q(stream->duration, stream->time_base,
                          {1, 1000});
   }
   return 0;
}

/**
 * @brief Открывает декодер потока.
 * @param stream - поток.
 * @return контекст или nullptr.
 */
AVCodecContext* open_decoder(AVStream* stream) {
   const AVCodec* codec =
       avcodec_find_decoder(stream->codecpar->codec_id);
   if (codec == nullptr) {
      return nullptr;
   }
   AVCodecContext* codec_ctx = avcodec_alloc_context3(codec);
   if (codec_ctx == nullptr) {
      return nullptr;
   }
   if (avcodec_parameters_to_context(codec_ctx, stream->codecpar) <
       0) {
      avcodec_free_context(&codec_ctx);
      return nullptr;
   }
   if (avcodec_open2(codec_ctx, codec, nullptr) < 0) {
      avcodec_free_context(&codec_ctx);
      return nullptr;
   }
   return codec_ctx;
}

constexpr int kSimdPad = 64;

/**
 * @brief Масштабирует кадр в BGRA с запасом под SIMD.
 * @param frame - декодированный кадр.
 * @return картинка или пустая.
 */
QImage frame_to_image(const AVFrame* frame) {
   if (frame == nullptr || frame->width <= 0 || frame->height <= 0) {
      return {};
   }
   SwsContext* sws = sws_getContext(
       frame->width, frame->height,
       static_cast<AVPixelFormat>(frame->format), frame->width,
       frame->height, AV_PIX_FMT_BGRA, SWS_BILINEAR, nullptr,
       nullptr, nullptr);
   if (sws == nullptr) {
      return {};
   }
   const int stride =
       (frame->width * 4 + kSimdPad - 1) & ~(kSimdPad - 1);
   std::vector<uint8_t> buffer(
       static_cast<std::size_t>(stride) * frame->height + kSimdPad);
   uint8_t* dest[1] = {buffer.data()};
   int dest_linesize[1] = {stride};
   sws_scale(sws, frame->data, frame->linesize, 0, frame->height,
             dest, dest_linesize);
   sws_freeContext(sws);
   QImage image(frame->width, frame->height, QImage::Format_ARGB32);
   if (image.isNull()) {
      return {};
   }
   for (int y = 0; y < frame->height; ++y) {
      std::memcpy(image.scanLine(y),
                  buffer.data() + static_cast<std::size_t>(y) * stride,
                  static_cast<std::size_t>(frame->width) * 4);
   }
   return image;
}

/**
 * @brief Число выходных сэмплов с запасом на delay.
 * @param swr - ресемплер.
 * @param in_rate - частота исходника.
 * @param in_samples - сэмплы кадра.
 * @return размер буфера >= 32.
 */
int resample_capacity_to(SwrContext* swr, int in_rate, int in_samples,
                         int out_rate) {
   if (in_rate <= 0 || in_samples < 0 || out_rate <= 0) {
      return 32;
   }
   const int64_t delay = swr_get_delay(swr, in_rate);
   const int64_t need = av_rescale_rnd(
       delay + in_samples, out_rate, in_rate, AV_ROUND_UP);
   return static_cast<int>(std::max<int64_t>(need + 32, 32));
}

int resample_capacity(SwrContext* swr, int in_rate, int in_samples) {
   return resample_capacity_to(swr, in_rate, in_samples, 8000);
}

int16_t scale_sample(int16_t sample, double volume) {
   const int value = static_cast<int>(std::lround(sample * volume));
   if (value > 32767) {
      return 32767;
   }
   if (value < -32768) {
      return -32768;
   }
   return static_cast<int16_t>(value);
}

}  // namespace

MediaInfo CMediaIo::probe(const QString& path) {
   MediaInfo info;
   AVFormatContext* format = open_input(path);
   if (format == nullptr) {
      return info;
   }
   info.duration_ms = duration_ms_of(format);
   const int video = find_stream(format, AVMEDIA_TYPE_VIDEO);
   const int audio = find_stream(format, AVMEDIA_TYPE_AUDIO);
   info.has_video = video >= 0;
   info.has_audio = audio >= 0;
   if (video >= 0) {
      const AVCodecParameters* par =
          format->streams[video]->codecpar;
      info.width = par->width;
      info.height = par->height;
   }
   avformat_close_input(&format);
   return info;
}

QImage CMediaIo::decode_frame(const QString& path, qint64 time_ms) {
   AVFormatContext* format = open_input(path);
   if (format == nullptr) {
      return {};
   }
   const int index = find_stream(format, AVMEDIA_TYPE_VIDEO);
   if (index < 0) {
      avformat_close_input(&format);
      return {};
   }
   AVStream* stream = format->streams[index];
   AVCodecContext* codec = open_decoder(stream);
   if (codec == nullptr) {
      avformat_close_input(&format);
      return {};
   }

   const qint64 stamp = std::max<qint64>(time_ms, 0);
   const int64_t ts =
       av_rescale_q(stamp, {1, 1000}, stream->time_base);
   av_seek_frame(format, index, ts, AVSEEK_FLAG_BACKWARD);
   avcodec_flush_buffers(codec);

   AVPacket* packet = av_packet_alloc();
   AVFrame* frame = av_frame_alloc();
   QImage image;
   bool got = false;
   while (av_read_frame(format, packet) >= 0) {
      if (packet->stream_index != index) {
         av_packet_unref(packet);
         continue;
      }
      if (avcodec_send_packet(codec, packet) < 0) {
         av_packet_unref(packet);
         break;
      }
      av_packet_unref(packet);
      while (avcodec_receive_frame(codec, frame) == 0) {
         const qint64 frame_ms = av_rescale_q(
             frame->best_effort_timestamp, stream->time_base,
             {1, 1000});
         if (frame_ms + 40 < stamp) {
            continue;
         }
         image = frame_to_image(frame);
         got = !image.isNull();
         break;
      }
      if (got) {
         break;
      }
   }
   av_frame_free(&frame);
   av_packet_free(&packet);
   avcodec_free_context(&codec);
   avformat_close_input(&format);
   return image;
}

bool CMediaIo::write_jpeg(const QImage& image, const QString& path) {
   if (image.isNull()) {
      return false;
   }
   QDir().mkpath(QFileInfo(path).absolutePath());
   if (image.save(path, "PNG")) {
      return true;
   }
   if (image.save(path, "JPG", 85)) {
      return true;
   }
   return image.save(path, "BMP");
}

std::vector<float> CMediaIo::waveform_peaks(const QString& path) {
   std::vector<float> peaks;
   AVFormatContext* format = open_input(path);
   if (format == nullptr) {
      return peaks;
   }
   const int index = find_stream(format, AVMEDIA_TYPE_AUDIO);
   if (index < 0) {
      avformat_close_input(&format);
      return peaks;
   }
   AVStream* stream = format->streams[index];
   AVCodecContext* codec = open_decoder(stream);
   if (codec == nullptr || codec->sample_rate <= 0) {
      avcodec_free_context(&codec);
      avformat_close_input(&format);
      return peaks;
   }

   AVChannelLayout mono = AV_CHANNEL_LAYOUT_MONO;
   SwrContext* swr = nullptr;
   if (swr_alloc_set_opts2(&swr, &mono, AV_SAMPLE_FMT_FLT, 8000,
                           &codec->ch_layout, codec->sample_fmt,
                           codec->sample_rate, 0, nullptr) < 0) {
      avcodec_free_context(&codec);
      avformat_close_input(&format);
      return peaks;
   }
   if (swr_init(swr) < 0) {
      swr_free(&swr);
      avcodec_free_context(&codec);
      avformat_close_input(&format);
      return peaks;
   }

   AVPacket* packet = av_packet_alloc();
   AVFrame* frame = av_frame_alloc();
   float peak = 0;
   int bin_samples = 0;
   constexpr int kBin = 160;
   while (av_read_frame(format, packet) >= 0) {
      if (packet->stream_index != index) {
         av_packet_unref(packet);
         continue;
      }
      if (avcodec_send_packet(codec, packet) < 0) {
         av_packet_unref(packet);
         break;
      }
      av_packet_unref(packet);
      while (avcodec_receive_frame(codec, frame) == 0) {
         const int max_out = resample_capacity(
             swr, codec->sample_rate, frame->nb_samples);
         std::vector<float> buffer(static_cast<std::size_t>(max_out));
         uint8_t* dest[1] = {
             reinterpret_cast<uint8_t*>(buffer.data())};
         const int converted = swr_convert(
             swr, dest, max_out,
             const_cast<const uint8_t**>(frame->extended_data),
             frame->nb_samples);
         if (converted < 0) {
            continue;
         }
         const int count =
             std::min(converted, static_cast<int>(buffer.size()));
         for (int i = 0; i < count; ++i) {
            const float sample =
                buffer[static_cast<std::size_t>(i)];
            peak = std::max(peak, std::fabs(sample));
            ++bin_samples;
            if (bin_samples >= kBin) {
               peaks.push_back(std::min(peak, 1.0f));
               peak = 0;
               bin_samples = 0;
            }
         }
      }
   }
   if (bin_samples > 0) {
      peaks.push_back(std::min(peak, 1.0f));
   }
   av_frame_free(&frame);
   av_packet_free(&packet);
   swr_free(&swr);
   avcodec_free_context(&codec);
   avformat_close_input(&format);
   return peaks;
}

QByteArray CMediaIo::decode_pcm(const QString& path, qint64 in_ms,
                                qint64 out_ms, double volume) {
   QByteArray pcm;
   if (path.isEmpty() || out_ms <= in_ms) {
      return pcm;
   }
   AVFormatContext* format = open_input(path);
   if (format == nullptr) {
      return pcm;
   }
   const int index = find_stream(format, AVMEDIA_TYPE_AUDIO);
   if (index < 0) {
      avformat_close_input(&format);
      return pcm;
   }
   AVStream* stream = format->streams[index];
   AVCodecContext* codec = open_decoder(stream);
   if (codec == nullptr || codec->sample_rate <= 0) {
      avcodec_free_context(&codec);
      avformat_close_input(&format);
      return pcm;
   }
   AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
   SwrContext* swr = nullptr;
   constexpr int kRate = 44100;
   if (swr_alloc_set_opts2(&swr, &stereo, AV_SAMPLE_FMT_S16, kRate,
                           &codec->ch_layout, codec->sample_fmt,
                           codec->sample_rate, 0, nullptr) < 0) {
      avcodec_free_context(&codec);
      avformat_close_input(&format);
      return pcm;
   }
   if (swr_init(swr) < 0) {
      swr_free(&swr);
      avcodec_free_context(&codec);
      avformat_close_input(&format);
      return pcm;
   }
   const int64_t stamp = av_rescale_q(
       std::max<qint64>(in_ms - 80, 0), {1, 1000}, stream->time_base);
   av_seek_frame(format, index, stamp, AVSEEK_FLAG_BACKWARD);
   avcodec_flush_buffers(codec);

   const int want = static_cast<int>((out_ms - in_ms) * kRate / 1000);
   pcm.resize(want * 4);
   pcm.fill(0);
   auto* dest_pcm = reinterpret_cast<int16_t*>(pcm.data());
   int written = 0;

   AVPacket* packet = av_packet_alloc();
   AVFrame* frame = av_frame_alloc();
   while (written < want && av_read_frame(format, packet) >= 0) {
      if (packet->stream_index != index) {
         av_packet_unref(packet);
         continue;
      }
      if (avcodec_send_packet(codec, packet) < 0) {
         av_packet_unref(packet);
         break;
      }
      av_packet_unref(packet);
      while (written < want && avcodec_receive_frame(codec, frame) == 0) {
         const int max_out = resample_capacity_to(
             swr, codec->sample_rate, frame->nb_samples, kRate);
         std::vector<int16_t> buffer(
             static_cast<std::size_t>(max_out) * 2u);
         uint8_t* dest[1] = {
             reinterpret_cast<uint8_t*>(buffer.data())};
         const int converted = swr_convert(
             swr, dest, max_out,
             const_cast<const uint8_t**>(frame->extended_data),
             frame->nb_samples);
         if (converted <= 0) {
            continue;
         }
         qint64 chunk_ms = in_ms;
         if (frame->best_effort_timestamp != AV_NOPTS_VALUE) {
            chunk_ms = av_rescale_q(frame->best_effort_timestamp,
                                    stream->time_base, {1, 1000});
         }
         int skip = 0;
         if (chunk_ms < in_ms) {
            skip = static_cast<int>((in_ms - chunk_ms) * kRate / 1000);
         }
         const int count = std::min(converted, max_out);
         for (int i = skip; i < count && written < want; ++i) {
            const qint64 sample_ms =
                chunk_ms + static_cast<qint64>(i) * 1000 / kRate;
            if (sample_ms < in_ms) {
               continue;
            }
            if (sample_ms >= out_ms) {
               written = want;
               break;
            }
            dest_pcm[written * 2] = scale_sample(
                buffer[static_cast<std::size_t>(i) * 2u], volume);
            dest_pcm[written * 2 + 1] = scale_sample(
                buffer[static_cast<std::size_t>(i) * 2u + 1u], volume);
            ++written;
         }
      }
   }
   av_frame_free(&frame);
   av_packet_free(&packet);
   swr_free(&swr);
   avcodec_free_context(&codec);
   avformat_close_input(&format);
   return pcm;
}

QString CMediaIo::copy_asset(const QString& library_root,
                             const QString& source_path,
                             const QString& asset_id) {
   const QFileInfo info(source_path);
   if (!info.isFile()) {
      return {};
   }
   const QString folder =
       QDir(library_root).filePath("media/" + asset_id);
   if (!QDir().mkpath(folder)) {
      return {};
   }
   const QString relative = "media/" + asset_id + "/" + info.fileName();
   const QString dest = QDir(library_root).filePath(relative);
   if (QFile::exists(dest)) {
      QFile::remove(dest);
   }
   if (!QFile::copy(source_path, dest)) {
      return {};
   }
   return relative;
}
