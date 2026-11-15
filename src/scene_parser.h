#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <vector>

/**
 * @brief Сцена ролика из сценария.
 */
struct Scene {
   QString prompt;
   int duration_s = 5;
};

/**
 * @brief Разбирает JSON сцен или цельный текст.
 * @param script - ответ чата или сплошной текст.
 * @return сцены с длительностью в [3, 20].
 */
std::vector<Scene> parse_scenes(const QString& script);

/**
 * @brief Разбор сцен для QML-тестов.
 */
class CSceneParser : public QObject {
   Q_OBJECT
   QML_ELEMENT

 public:
   /**
    * @brief Создаёт разборщик.
    * @param parent - владелец.
    */
   explicit CSceneParser(QObject* parent = nullptr);

   /**
    * @brief Разбирает сценарий в список сцен.
    * @param script - JSON или текст.
    * @return объекты prompt и duration_s.
    */
   Q_INVOKABLE QVariantList parse(const QString& script) const;
};
