#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

/**
 * @brief Иконка заголовка и сохранённое положение окна.
 */
class CWindowState : public QObject {
   Q_OBJECT
   QML_NAMED_ELEMENT(WindowState)
   QML_SINGLETON

 public:
   /**
    * @brief Создаёт состояние окна.
    * @param parent - владелец объекта.
    */
   explicit CWindowState(QObject* parent = nullptr);

   /**
    * @brief Ставит чёрный знак в заголовок окна.
    * @param window - главное окно.
    * @return true, если значок загружен.
    */
   Q_INVOKABLE bool apply_icon(QObject* window);

   /**
    * @brief Запоминает положение и размер окна.
    * @param window - главное окно.
    */
   Q_INVOKABLE void save_geometry(QObject* window);

   /**
    * @brief Возвращает окно на сохранённое место.
    * @param window - главное окно.
    */
   Q_INVOKABLE void restore_geometry(QObject* window);
};
