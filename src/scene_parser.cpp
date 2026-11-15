#include "scene_parser.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantMap>

namespace {

constexpr int kMinDurationS = 3;
constexpr int kMaxDurationS = 20;
constexpr int kDefaultDurationS = 5;

int clamp_duration(int value) {
   if (value < kMinDurationS) {
      return kMinDurationS;
   }
   if (value > kMaxDurationS) {
      return kMaxDurationS;
   }
   return value;
}

std::vector<Scene> one_scene(const QString& script) {
   Scene scene;
   scene.prompt = script.trimmed();
   scene.duration_s = kDefaultDurationS;
   return {scene};
}

QJsonObject first_object(const QString& script) {
   const int start = script.indexOf(QLatin1Char('{'));
   const int end = script.lastIndexOf(QLatin1Char('}'));
   if (start < 0 || end <= start) {
      return {};
   }
   const QByteArray slice =
       script.mid(start, end - start + 1).toUtf8();
   const QJsonDocument document = QJsonDocument::fromJson(slice);
   if (!document.isObject()) {
      return {};
   }
   return document.object();
}

}  // namespace

std::vector<Scene> parse_scenes(const QString& script) {
   const QJsonObject object = first_object(script);
   if (!object.contains(QStringLiteral("scenes")) ||
       !object.value(QStringLiteral("scenes")).isArray()) {
      return one_scene(script);
   }
   const QJsonArray items =
       object.value(QStringLiteral("scenes")).toArray();
   if (items.isEmpty()) {
      return one_scene(script);
   }
   std::vector<Scene> scenes;
   for (const QJsonValue& value : items) {
      const QJsonObject item = value.toObject();
      Scene scene;
      scene.prompt = item.value(QStringLiteral("prompt")).toString();
      const int duration =
          item.value(QStringLiteral("duration_s")).toInt(
              kDefaultDurationS);
      scene.duration_s = clamp_duration(duration);
      scenes.push_back(scene);
   }
   if (scenes.empty()) {
      return one_scene(script);
   }
   return scenes;
}

CSceneParser::CSceneParser(QObject* parent) : QObject(parent) {}

QVariantList CSceneParser::parse(const QString& script) const {
   QVariantList list;
   for (const Scene& scene : parse_scenes(script)) {
      QVariantMap item;
      item.insert(QStringLiteral("prompt"), scene.prompt);
      item.insert(QStringLiteral("duration_s"), scene.duration_s);
      list.append(item);
   }
   return list;
}
