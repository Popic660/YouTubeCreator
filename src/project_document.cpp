#include "project_document.h"

#include "media_io.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QUrl>
#include <QUuid>

#include <algorithm>

namespace {

constexpr qint64 kTickMs = 40;

/**
 * @brief Локальный путь из file-URL или строки.
 * @param value - путь.
 * @return очищенный путь.
 */
QString local_path(const QString& value) {
   const QUrl url(value);
   if (url.isLocalFile()) {
      return QDir::cleanPath(url.toLocalFile());
   }
   return QDir::cleanPath(value);
}

/**
 * @brief Имя без расширения.
 * @param path - файл.
 * @return база имени.
 */
QString base_name(const QString& path) {
   return QFileInfo(path).completeBaseName();
}

/**
 * @brief Клип покрывает время таймлайна.
 * @param clip - клип.
 * @param time_ms - ползунок.
 * @return true, если кадр внутри клипа.
 */
bool covers(const TimelineClip& clip, qint64 time_ms) {
   const qint64 length = clip.out_ms - clip.in_ms;
   return time_ms >= clip.start_ms &&
          time_ms < clip.start_ms + length;
}

}  // namespace

CProjectDocument::CProjectDocument(QObject* parent)
    : QObject(parent) {
   play_timer_.setInterval(static_cast<int>(kTickMs));
   connect(&play_timer_, &QTimer::timeout, this,
           &CProjectDocument::tick_play);
}

void CProjectDocument::set_store(CLibraryStore* store) {
   if (store_ == store) {
      return;
   }
   if (store_ != nullptr) {
      disconnect(store_, nullptr, this, nullptr);
   }
   store_ = store;
   if (store_ != nullptr) {
      connect(store_, &CLibraryStore::library_changed, this,
              [this]() {
                 if (!short_id_.isEmpty() &&
                     store_->short_name(short_id_).isEmpty()) {
                    close();
                 }
              });
   }
   close();
   emit store_changed();
}

void CProjectDocument::set_playhead_ms(qint64 time_ms) {
   const qint64 clamped = std::max<qint64>(time_ms, 0);
   if (playhead_ms_ == clamped) {
      return;
   }
   playhead_ms_ = clamped;
   emit playhead_changed();
}

void CProjectDocument::set_selected_clip_id(const QString& id) {
   if (selected_clip_id_ == id) {
      return;
   }
   selected_clip_id_ = id;
   emit selection_changed();
}

int CProjectDocument::clip_count() const {
   return count_track(QStringLiteral("v1"));
}

int CProjectDocument::audio_count() const {
   return count_track(QStringLiteral("a1"));
}

int CProjectDocument::text_count() const {
   return count_track(QStringLiteral("v2"));
}

int CProjectDocument::item_count() const {
   return static_cast<int>(clips_.size());
}

int CProjectDocument::count_track(const QString& track) const {
   int count = 0;
   for (const TimelineClip& clip : clips_) {
      if (clip.track == track) {
         ++count;
      }
   }
   return count;
}

bool CProjectDocument::open_short(const QString& short_id) {
   pause();
   if (store_ == nullptr || store_->short_name(short_id).isEmpty()) {
      close();
      return false;
   }
   short_id_ = short_id;
   selected_clip_id_.clear();
   playhead_ms_ = 0;
   undo_.clear();
   load_json();
   emit short_changed();
   emit timeline_changed();
   emit playhead_changed();
   emit selection_changed();
   return true;
}

void CProjectDocument::close() {
   pause();
   const bool had = !short_id_.isEmpty() || !clips_.empty();
   short_id_.clear();
   clips_.clear();
   undo_.clear();
   selected_clip_id_.clear();
   playhead_ms_ = 0;
   if (had) {
      emit short_changed();
      emit timeline_changed();
      emit playhead_changed();
      emit selection_changed();
   }
}

QString CProjectDocument::import_video(const QString& folder_id,
                                       const QString& path) {
   if (store_ == nullptr) {
      return {};
   }
   const QString file = local_path(path);
   if (file.isEmpty() || !QFileInfo::exists(file)) {
      return {};
   }
   const QString name = base_name(file);
   const QString id = store_->create_short(folder_id, name);
   if (id.isEmpty()) {
      return {};
   }
   if (!attach_media(id, file, true)) {
      store_->delete_short(id, true);
      return {};
   }
   open_short(id);
   return id;
}

bool CProjectDocument::import_into_short(const QString& short_id,
                                         const QString& path) {
   const QString file = local_path(path);
   if (file.isEmpty() || !QFileInfo::exists(file)) {
      return false;
   }
   if (!attach_media(short_id, file, true)) {
      return false;
   }
   if (short_id_ == short_id) {
      load_json();
      emit timeline_changed();
   }
   return true;
}

QString CProjectDocument::add_audio(const QString& path) {
   if (store_ == nullptr || short_id_.isEmpty()) {
      return {};
   }
   const QString file = local_path(path);
   const MediaInfo info = CMediaIo::probe(file);
   if (info.duration_ms <= 0) {
      return {};
   }
   const QString asset =
       QUuid::createUuid().toString(QUuid::WithoutBraces);
   const QString relative =
       CMediaIo::copy_asset(store_->root_path(), file, asset);
   if (relative.isEmpty()) {
      return {};
   }
   push_undo();
   TimelineClip clip;
   clip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
   clip.track = QStringLiteral("a1");
   clip.kind = QStringLiteral("audio");
   clip.asset_id = asset;
   clip.file = relative;
   clip.out_ms = info.duration_ms;
   clips_.push_back(clip);
   write_waveform(asset, QDir(store_->root_path()).filePath(relative));
   save();
   emit timeline_changed();
   return clip.id;
}

QString CProjectDocument::add_text(const QString& text) {
   if (short_id_.isEmpty() || text.trimmed().isEmpty()) {
      return {};
   }
   push_undo();
   TimelineClip clip;
   clip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
   clip.track = QStringLiteral("v2");
   clip.kind = QStringLiteral("text");
   clip.text = text;
   clip.out_ms = std::max<qint64>(duration_ms(), 1000);
   clips_.push_back(clip);
   selected_clip_id_ = clip.id;
   save();
   emit timeline_changed();
   emit selection_changed();
   return clip.id;
}

bool CProjectDocument::split_at_playhead() {
   TimelineClip* clip = mutable_clip(selected_clip_id_);
   if (clip == nullptr) {
      for (TimelineClip& item : clips_) {
         if (item.track == QLatin1String("v1") &&
             covers(item, playhead_ms_)) {
            clip = &item;
            break;
         }
      }
   }
   if (clip == nullptr || !covers(*clip, playhead_ms_)) {
      return false;
   }
   const qint64 local = clip->in_ms + (playhead_ms_ - clip->start_ms);
   if (local <= clip->in_ms || local >= clip->out_ms) {
      return false;
   }
   push_undo();
   TimelineClip right = *clip;
   right.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
   right.in_ms = local;
   right.start_ms = playhead_ms_;
   clip->out_ms = local;
   clips_.push_back(right);
   save();
   emit timeline_changed();
   return true;
}

bool CProjectDocument::trim_clip(const QString& clip_id, qint64 in_ms,
                                 qint64 out_ms) {
   TimelineClip* clip = mutable_clip(clip_id);
   if (clip == nullptr || out_ms <= in_ms) {
      return false;
   }
   push_undo();
   clip->in_ms = in_ms;
   clip->out_ms = out_ms;
   save();
   emit timeline_changed();
   return true;
}

bool CProjectDocument::set_volume(const QString& clip_id,
                                  double volume) {
   TimelineClip* clip = mutable_clip(clip_id);
   if (clip == nullptr) {
      return false;
   }
   push_undo();
   clip->volume = volume;
   save();
   emit timeline_changed();
   return true;
}

bool CProjectDocument::set_transform(const QString& clip_id,
                                     double scale, double offset_x,
                                     double offset_y) {
   TimelineClip* clip = mutable_clip(clip_id);
   if (clip == nullptr) {
      return false;
   }
   push_undo();
   clip->scale = scale;
   clip->offset_x = offset_x;
   clip->offset_y = offset_y;
   save();
   emit timeline_changed();
   return true;
}

bool CProjectDocument::apply_cover() {
   TimelineClip* clip = mutable_clip(selected_clip_id_);
   if (clip == nullptr) {
      clip = mutable_clip(first_clip_on(QStringLiteral("v1")));
   }
   if (clip == nullptr) {
      return false;
   }
   push_undo();
   clip->scale = 1.0;
   clip->offset_x = 0;
   clip->offset_y = 0;
   save();
   emit timeline_changed();
   return true;
}

bool CProjectDocument::delete_selected_clip() {
   if (selected_clip_id_.isEmpty()) {
      selected_clip_id_ = first_clip_on(QStringLiteral("v1"));
   }
   if (selected_clip_id_.isEmpty()) {
      return false;
   }
   auto it = std::find_if(
       clips_.begin(), clips_.end(), [&](const TimelineClip& clip) {
          return clip.id == selected_clip_id_;
       });
   if (it == clips_.end()) {
      return false;
   }
   push_undo();
   clips_.erase(it);
   selected_clip_id_.clear();
   save();
   emit timeline_changed();
   emit selection_changed();
   return true;
}

bool CProjectDocument::undo() {
   if (undo_.empty()) {
      return false;
   }
   const QByteArray dumped = undo_.back();
   undo_.pop_back();
   from_json(QJsonDocument::fromJson(dumped).object());
   save();
   emit timeline_changed();
   return true;
}

void CProjectDocument::play() {
   if (!has_clips()) {
      return;
   }
   if (playhead_ms_ >= duration_ms()) {
      set_playhead_ms(0);
   }
   playing_ = true;
   play_timer_.start();
   emit playing_changed();
}

void CProjectDocument::pause() {
   if (!playing_) {
      play_timer_.stop();
      return;
   }
   playing_ = false;
   play_timer_.stop();
   emit playing_changed();
}

void CProjectDocument::toggle_play() {
   if (playing_) {
      pause();
      return;
   }
   play();
}

bool CProjectDocument::save() {
   if (store_ == nullptr || short_id_.isEmpty()) {
      return false;
   }
   const QString path = project_path();
   QDir().mkpath(QFileInfo(path).absolutePath());
   QFile file(path);
   if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
      return false;
   }
   file.write(QJsonDocument(to_json()).toJson());
   return true;
}

QString CProjectDocument::clip_id_at(int index) const {
   if (index < 0 || index >= static_cast<int>(clips_.size())) {
      return {};
   }
   return clips_[static_cast<std::size_t>(index)].id;
}

QString CProjectDocument::clip_track(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   return clip == nullptr ? QString() : clip->track;
}

qint64 CProjectDocument::clip_in(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   return clip == nullptr ? 0 : clip->in_ms;
}

qint64 CProjectDocument::clip_out(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   return clip == nullptr ? 0 : clip->out_ms;
}

qint64 CProjectDocument::clip_start(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   return clip == nullptr ? 0 : clip->start_ms;
}

double CProjectDocument::clip_volume(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   return clip == nullptr ? 1.0 : clip->volume;
}

double CProjectDocument::clip_scale(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   return clip == nullptr ? 1.0 : clip->scale;
}

double CProjectDocument::clip_offset_x(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   return clip == nullptr ? 0 : clip->offset_x;
}

double CProjectDocument::clip_offset_y(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   return clip == nullptr ? 0 : clip->offset_y;
}

QString CProjectDocument::clip_text(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   return clip == nullptr ? QString() : clip->text;
}

QString CProjectDocument::first_clip_on(const QString& track) const {
   for (const TimelineClip& clip : clips_) {
      if (clip.track == track) {
         return clip.id;
      }
   }
   return {};
}

QString CProjectDocument::clip_abs_path(const QString& clip_id) const {
   const TimelineClip* clip = clip_by_id(clip_id);
   if (clip == nullptr || store_ == nullptr || clip->file.isEmpty()) {
      return {};
   }
   return QDir(store_->root_path()).filePath(clip->file);
}

const TimelineClip* CProjectDocument::video_at(qint64 time_ms) const {
   for (const TimelineClip& clip : clips_) {
      if (clip.track == QLatin1String("v1") && covers(clip, time_ms)) {
         return &clip;
      }
   }
   return nullptr;
}

std::vector<const TimelineClip*> CProjectDocument::overlays_at(
    qint64 time_ms) const {
   std::vector<const TimelineClip*> result;
   for (const TimelineClip& clip : clips_) {
      if (clip.track == QLatin1String("v2") && covers(clip, time_ms)) {
         result.push_back(&clip);
      }
   }
   return result;
}

qint64 CProjectDocument::duration_ms() const {
   qint64 end = 0;
   for (const TimelineClip& clip : clips_) {
      end = std::max(end, clip.start_ms + (clip.out_ms - clip.in_ms));
   }
   return end;
}

QString CProjectDocument::project_path() const {
   if (store_ == nullptr || short_id_.isEmpty()) {
      return {};
   }
   return QDir(store_->root_path())
       .filePath("shorts/" + short_id_ + "/project.json");
}

bool CProjectDocument::has_waveform(const QString& asset_id) const {
   if (store_ == nullptr || asset_id.isEmpty()) {
      return false;
   }
   return QFileInfo::exists(
       QDir(store_->root_path())
           .filePath("cache/waveforms/" + asset_id));
}

TimelineClip* CProjectDocument::mutable_clip(const QString& id) {
   return const_cast<TimelineClip*>(clip_by_id(id));
}

const TimelineClip* CProjectDocument::clip_by_id(
    const QString& id) const {
   for (const TimelineClip& clip : clips_) {
      if (clip.id == id) {
         return &clip;
      }
   }
   return nullptr;
}

void CProjectDocument::push_undo() {
   undo_.push_back(QJsonDocument(to_json()).toJson(QJsonDocument::Compact));
}

void CProjectDocument::load_json() {
   clips_.clear();
   QFile file(project_path());
   if (!file.open(QIODevice::ReadOnly)) {
      return;
   }
   from_json(QJsonDocument::fromJson(file.readAll()).object());
}

QJsonObject CProjectDocument::to_json() const {
   QJsonArray items;
   for (const TimelineClip& clip : clips_) {
      QJsonObject object;
      object["id"] = clip.id;
      object["track"] = clip.track;
      object["kind"] = clip.kind;
      object["asset_id"] = clip.asset_id;
      object["file"] = clip.file;
      object["in_ms"] = clip.in_ms;
      object["out_ms"] = clip.out_ms;
      object["start_ms"] = clip.start_ms;
      object["scale"] = clip.scale;
      object["offset_x"] = clip.offset_x;
      object["offset_y"] = clip.offset_y;
      object["volume"] = clip.volume;
      object["text"] = clip.text;
      items.append(object);
   }
   QJsonObject root;
   root["version"] = 1;
   root["playhead_ms"] = playhead_ms_;
   root["clips"] = items;
   return root;
}

void CProjectDocument::from_json(const QJsonObject& object) {
   clips_.clear();
   playhead_ms_ = object["playhead_ms"].toInteger();
   const QJsonArray items = object["clips"].toArray();
   for (const QJsonValue& value : items) {
      const QJsonObject item = value.toObject();
      TimelineClip clip;
      clip.id = item["id"].toString();
      clip.track = item["track"].toString();
      clip.kind = item["kind"].toString();
      clip.asset_id = item["asset_id"].toString();
      clip.file = item["file"].toString();
      clip.in_ms = item["in_ms"].toInteger();
      clip.out_ms = item["out_ms"].toInteger();
      clip.start_ms = item["start_ms"].toInteger();
      clip.scale = item["scale"].toDouble(1.0);
      clip.offset_x = item["offset_x"].toDouble();
      clip.offset_y = item["offset_y"].toDouble();
      clip.volume = item["volume"].toDouble(1.0);
      clip.text = item["text"].toString();
      clips_.push_back(clip);
   }
}

bool CProjectDocument::attach_media(const QString& short_id,
                                    const QString& path,
                                    bool keep_name) {
   Q_UNUSED(keep_name)
   if (store_ == nullptr) {
      return false;
   }
   const MediaInfo info = CMediaIo::probe(path);
   if (!info.has_video || info.duration_ms <= 0) {
      return false;
   }
   const QString asset =
       QUuid::createUuid().toString(QUuid::WithoutBraces);
   const QString relative =
       CMediaIo::copy_asset(store_->root_path(), path, asset);
   if (relative.isEmpty()) {
      return false;
   }
   const std::vector<TimelineClip> saved_clips = clips_;
   const QString saved_short = short_id_;
   TimelineClip video;
   video.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
   video.track = QStringLiteral("v1");
   video.kind = QStringLiteral("video");
   video.asset_id = asset;
   video.file = relative;
   video.out_ms = info.duration_ms;
   clips_.clear();
   clips_.push_back(video);
   if (info.has_audio) {
      TimelineClip audio = video;
      audio.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
      audio.track = QStringLiteral("a1");
      audio.kind = QStringLiteral("audio");
      clips_.push_back(audio);
      write_waveform(
          asset, QDir(store_->root_path()).filePath(relative));
   }
   short_id_ = short_id;
   const QString poster = write_poster(
       short_id, QDir(store_->root_path()).filePath(relative));
   save();
   store_->update_short_media(short_id, info.duration_ms, poster);
   short_id_ = saved_short;
   clips_ = saved_clips;
   return true;
}

QString CProjectDocument::write_poster(const QString& short_id,
                                       const QString& file) {
   QImage frame = CMediaIo::decode_frame(file, 0);
   if (frame.isNull()) {
      frame = QImage(72, 128, QImage::Format_ARGB32);
      frame.fill(QColor("#212121"));
   }
   const QString relative = "shorts/" + short_id + "/poster.png";
   const QString dest = QDir(store_->root_path()).filePath(relative);
   if (!CMediaIo::write_jpeg(frame, dest)) {
      return {};
   }
   return relative;
}

void CProjectDocument::write_waveform(const QString& asset_id,
                                      const QString& file) {
   const std::vector<float> peaks = CMediaIo::waveform_peaks(file);
   if (peaks.empty()) {
      return;
   }
   const QString dest = QDir(store_->root_path())
                            .filePath("cache/waveforms/" + asset_id);
   QDir().mkpath(QFileInfo(dest).absolutePath());
   QFile out(dest);
   if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
      return;
   }
   QJsonArray values;
   for (float peak : peaks) {
      values.append(peak);
   }
   out.write(QJsonDocument(values).toJson(QJsonDocument::Compact));
}

void CProjectDocument::tick_play() {
   const qint64 next = playhead_ms_ + kTickMs;
   if (next >= duration_ms()) {
      set_playhead_ms(duration_ms());
      pause();
      return;
   }
   set_playhead_ms(next);
}
