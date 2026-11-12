#pragma once

#include <QByteArray>
#include <QImage>
#include <QString>

#include <vector>

/**
 * @brief Сведения о медиафайле.
 */
struct MediaInfo {
   qint64 duration_ms = 0;
   int width = 0;
   int height = 0;
   bool has_video = false;
   bool has_audio = false;
};

/**
 * @brief Чтение длительности, кадра и волны через FFmpeg.
 */
class CMediaIo {
 public:
   /**
    * @brief Читает длительность и наличие дорожек.
    * @param path - локальный файл.
    * @return сведения или нули, если файл не открылся.
    */
   static MediaInfo probe(const QString& path);

   /**
    * @brief Декодирует кадр в заданное время исходника.
    * @param path - локальный файл.
    * @param time_ms - время в исходнике.
    * @return RGB-картинка или пустая.
    */
   static QImage decode_frame(const QString& path, qint64 time_ms);

   /**
    * @brief Пишет JPEG.
    * @param image - картинка.
    * @param path - путь файла.
    * @return true, если файл записан.
    */
   static bool write_jpeg(const QImage& image, const QString& path);

   /**
    * @brief Считает пики звука 0..1.
    * @param path - локальный файл.
    * @return пики; пусто, если звука нет.
    */
   static std::vector<float> waveform_peaks(const QString& path);

   /**
    * @brief Декодирует фрагмент в PCM s16le stereo 44100.
    * @param path - локальный файл.
    * @param in_ms - вход исходника.
    * @param out_ms - выход исходника.
    * @param volume - коэффициент громкости.
    * @return байты PCM или пусто.
    */
   static QByteArray decode_pcm(const QString& path, qint64 in_ms,
                                qint64 out_ms, double volume);

   /**
    * @brief Копирует файл в media/<asset_id>/.
    * @param library_root - папка библиотеки.
    * @param source_path - исходник.
    * @param asset_id - id ассета.
    * @return относительный путь внутри библиотеки.
    */
   static QString copy_asset(const QString& library_root,
                             const QString& source_path,
                             const QString& asset_id);
};
