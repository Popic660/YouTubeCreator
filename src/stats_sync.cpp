#include "stats_sync.h"

#include <QDate>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>
#include <QUrlQuery>

namespace {

constexpr char kVideosUrl[] =
    "https://www.googleapis.com/youtube/v3/videos";
constexpr char kChannelsUrl[] =
    "https://www.googleapis.com/youtube/v3/channels";
constexpr char kReportsUrl[] =
    "https://youtubeanalytics.googleapis.com/v2/reports";
constexpr char kMissing[] = "нет в этом канале";

QString json_stat(const QJsonObject& statistics, const char* key) {
   return statistics.value(QString::fromUtf8(key)).toString();
}

int header_index(const QJsonArray& headers, const QString& name) {
   for (int i = 0; i < headers.size(); ++i) {
      const QJsonObject header = headers.at(i).toObject();
      if (header.value(QStringLiteral("name")).toString() == name) {
         return i;
      }
   }
   return -1;
}

QJsonValue cell_or_missing(const QJsonArray& row, int index) {
   if (index < 0 || index >= row.size()) {
      return QString::fromUtf8(kMissing);
   }
   return row.at(index);
}

}  // namespace

CStatsSync::CStatsSync(QObject* parent) : QObject(parent) {}

CLibraryStore* CStatsSync::store() const {
   return store_;
}

void CStatsSync::set_store(CLibraryStore* store) {
   if (store_ == store) {
      return;
   }
   store_ = store;
   emit store_changed();
}

CChannelAuth* CStatsSync::auth() const {
   return auth_;
}

void CStatsSync::set_auth(CChannelAuth* auth) {
   if (auth_ == auth) {
      return;
   }
   auth_ = auth;
   emit auth_changed();
}

CHttpTransport* CStatsSync::transport() const {
   return transport_;
}

void CStatsSync::set_transport(CHttpTransport* transport) {
   if (transport_ == transport) {
      return;
   }
   transport_ = transport;
   emit transport_changed();
}

QString CStatsSync::last_error() const {
   return last_error_;
}

void CStatsSync::set_error(const QString& text) {
   last_error_ = text;
}

QString CStatsSync::bearer(const QString& token) const {
   return QStringLiteral("Bearer %1").arg(token);
}

QString CStatsSync::channel_for_video(const QString& video_id) const {
   const int count = store_->publication_count();
   for (int i = 0; i < count; ++i) {
      const QString id = store_->publication_id_at({}, i);
      if (store_->publication_video_id(id) == video_id) {
         return store_->publication_channel_id(id);
      }
   }
   return {};
}

QJsonObject CStatsSync::fetch_list(const QString& url,
                                   const QString& token) {
   const HttpResponse response =
       transport_->get_response(url, bearer(token));
   if (!response.error.isEmpty() || response.status >= 400) {
      const QString api = http_api_message(response);
      set_error(api.isEmpty() ? response.error : api);
      return {};
   }
   return QJsonDocument::fromJson(response.body).object();
}

QJsonObject CStatsSync::fetch_report(const QString& channel_id,
                                     const QString& video_id,
                                     const QString& token) {
   const QDate end = QDate::currentDate();
   const QDate start = end.addDays(-89);
   QUrl url(QString::fromUtf8(kReportsUrl));
   QUrlQuery query;
   query.addQueryItem(QStringLiteral("ids"),
                      QStringLiteral("channel==") + channel_id);
   query.addQueryItem(QStringLiteral("startDate"),
                      start.toString(Qt::ISODate));
   query.addQueryItem(QStringLiteral("endDate"),
                      end.toString(Qt::ISODate));
   query.addQueryItem(
       QStringLiteral("metrics"),
       QStringLiteral(
           "views,estimatedMinutesWatched,averageViewDuration,"
           "likes,impressions,impressionClickThroughRate"));
   query.addQueryItem(QStringLiteral("dimensions"),
                      QStringLiteral("day"));
   if (!video_id.isEmpty()) {
      query.addQueryItem(QStringLiteral("filters"),
                         QStringLiteral("video==") + video_id);
   }
   url.setQuery(query);
   const HttpResponse response = transport_->get_response(
       url.toString(QUrl::FullyEncoded), bearer(token));
   if (!response.error.isEmpty() || response.status >= 400) {
      const QString api = http_api_message(response);
      set_error(api.isEmpty() ? response.error : api);
      return {};
   }
   return QJsonDocument::fromJson(response.body).object();
}

QJsonObject CStatsSync::build_payload(const QString& kind,
                                      const QJsonObject& list,
                                      const QJsonObject& report) const {
   QJsonObject payload;
   const QJsonObject statistics =
       list.value(QStringLiteral("items"))
           .toArray()
           .at(0)
           .toObject()
           .value(QStringLiteral("statistics"))
           .toObject();
   if (kind == QLatin1String("video")) {
      payload.insert(QStringLiteral("views"),
                     json_stat(statistics, "viewCount"));
      payload.insert(QStringLiteral("likes"),
                     json_stat(statistics, "likeCount"));
      payload.insert(QStringLiteral("comments"),
                     json_stat(statistics, "commentCount"));
   } else {
      payload.insert(QStringLiteral("subscribers"),
                     json_stat(statistics, "subscriberCount"));
      payload.insert(QStringLiteral("views"),
                     json_stat(statistics, "viewCount"));
   }
   const QJsonArray headers =
       report.value(QStringLiteral("columnHeaders")).toArray();
   const int views_i =
       header_index(headers, QStringLiteral("views"));
   const int watch_i = header_index(
       headers, QStringLiteral("estimatedMinutesWatched"));
   const int avg_i = header_index(
       headers, QStringLiteral("averageViewDuration"));
   const int likes_i =
       header_index(headers, QStringLiteral("likes"));
   const int impressions_i =
       header_index(headers, QStringLiteral("impressions"));
   const int ctr_i = header_index(
       headers, QStringLiteral("impressionClickThroughRate"));
   const QJsonArray rows =
       report.value(QStringLiteral("rows")).toArray();
   QJsonArray points;
   qint64 views = 0;
   qint64 watch = 0;
   qint64 likes = 0;
   double avg = 0;
   bool has_avg = false;
   QJsonValue impressions = QString::fromUtf8(kMissing);
   QJsonValue ctr = QString::fromUtf8(kMissing);
   for (const QJsonValue& value : rows) {
      const QJsonArray row = value.toArray();
      QJsonObject point;
      const int day_i = header_index(headers, QStringLiteral("day"));
      if (day_i >= 0 && day_i < row.size()) {
         point.insert(QStringLiteral("day"), row.at(day_i));
      }
      if (views_i >= 0 && views_i < row.size()) {
         const qint64 day_views =
             row.at(views_i).toVariant().toLongLong();
         views += day_views;
         point.insert(QStringLiteral("views"), day_views);
      }
      if (watch_i >= 0 && watch_i < row.size()) {
         const qint64 day_watch =
             row.at(watch_i).toVariant().toLongLong();
         watch += day_watch;
         point.insert(QStringLiteral("watch"), day_watch);
      }
      if (avg_i >= 0 && avg_i < row.size()) {
         const double day_avg = row.at(avg_i).toDouble();
         avg += day_avg;
         has_avg = true;
         point.insert(QStringLiteral("avg"), day_avg);
      }
      if (likes_i >= 0 && likes_i < row.size()) {
         const qint64 day_likes =
             row.at(likes_i).toVariant().toLongLong();
         likes += day_likes;
         point.insert(QStringLiteral("likes"), day_likes);
      }
      points.append(point);
      if (impressions_i >= 0) {
         impressions = cell_or_missing(row, impressions_i);
      }
      if (ctr_i >= 0) {
         ctr = cell_or_missing(row, ctr_i);
      }
   }
   payload.insert(QStringLiteral("watch_time"), watch);
   if (has_avg && !rows.isEmpty()) {
      payload.insert(QStringLiteral("avg_duration"),
                     avg / static_cast<double>(rows.size()));
   } else {
      payload.insert(QStringLiteral("avg_duration"), 0);
   }
   if (kind == QLatin1String("video") &&
       payload.value(QStringLiteral("likes")).toString().isEmpty()) {
      payload.insert(QStringLiteral("likes"), likes);
   }
   payload.insert(QStringLiteral("impressions"), impressions);
   payload.insert(QStringLiteral("ctr"), ctr);
   payload.insert(QStringLiteral("points"), points);
   if (payload.value(QStringLiteral("views")).toString().isEmpty() &&
       views > 0) {
      payload.insert(QStringLiteral("views"), views);
   }
   return payload;
}

bool CStatsSync::refresh(const QString& kind,
                         const QString& target_id) {
   last_error_.clear();
   if (store_ == nullptr || auth_ == nullptr ||
       transport_ == nullptr) {
      set_error(QStringLiteral("missing bindings"));
      emit finished();
      return false;
   }
   const QString type = kind.trimmed();
   const QString target = target_id.trimmed();
   if (type != QLatin1String("channel") &&
       type != QLatin1String("video")) {
      set_error(QStringLiteral("unknown kind"));
      emit finished();
      return false;
   }
   if (target.isEmpty()) {
      set_error(QStringLiteral("missing target"));
      emit finished();
      return false;
   }
   QString channel_id = target;
   QString video_id;
   if (type == QLatin1String("video")) {
      video_id = target;
      channel_id = channel_for_video(video_id);
      if (channel_id.isEmpty()) {
         set_error(QStringLiteral("missing channel"));
         emit finished();
         return false;
      }
   }
   const QString token = auth_->access_token(channel_id);
   if (token.isEmpty()) {
      set_error(auth_->last_error().isEmpty()
                    ? QStringLiteral("missing refresh_token")
                    : auth_->last_error());
      emit finished();
      return false;
   }
   QUrl list_url(QString::fromUtf8(
       type == QLatin1String("video") ? kVideosUrl : kChannelsUrl));
   QUrlQuery list_query;
   list_query.addQueryItem(QStringLiteral("part"),
                           QStringLiteral("statistics"));
   list_query.addQueryItem(QStringLiteral("id"),
                           type == QLatin1String("video") ? video_id
                                                          : channel_id);
   list_url.setQuery(list_query);
   const QJsonObject list = fetch_list(
       list_url.toString(QUrl::FullyEncoded), token);
   if (list.isEmpty() && !last_error_.isEmpty()) {
      emit finished();
      return false;
   }
   const QJsonObject report =
       fetch_report(channel_id, video_id, token);
   if (report.isEmpty() && !last_error_.isEmpty()) {
      emit finished();
      return false;
   }
   const QJsonObject payload = build_payload(type, list, report);
   const QByteArray json =
       QJsonDocument(payload).toJson(QJsonDocument::Compact);
   if (!store_->upsert_stats(type, target, QString::fromUtf8(json))) {
      set_error(QStringLiteral("store failed"));
      emit finished();
      return false;
   }
   emit finished();
   return true;
}
