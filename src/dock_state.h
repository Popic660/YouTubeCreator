#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

/**
 * @brief Размеры доков и то, в каком доке лежит панель.
 */
class CDockState : public QObject {
   Q_OBJECT
   QML_NAMED_ELEMENT(DockState)
   QML_SINGLETON
   Q_PROPERTY(QString libraryDock READ library_dock
                  WRITE set_library_dock NOTIFY layout_changed)
   Q_PROPERTY(QString timelineDock READ timeline_dock
                  WRITE set_timeline_dock NOTIFY layout_changed)
   Q_PROPERTY(QString mediaDock READ media_dock WRITE set_media_dock
                  NOTIFY layout_changed)
   Q_PROPERTY(bool snapEnabled READ snap_enabled
                  WRITE set_snap_enabled NOTIFY layout_changed)
   Q_PROPERTY(int leftWidth READ left_width WRITE set_left_width
                  NOTIFY layout_changed)
   Q_PROPERTY(int rightWidth READ right_width WRITE set_right_width
                  NOTIFY layout_changed)
   Q_PROPERTY(int bottomHeight READ bottom_height
                  WRITE set_bottom_height NOTIFY layout_changed)

 public:
   /**
    * @brief Создаёт состояние раскладки.
    * @param parent - владелец объекта.
    */
   explicit CDockState(QObject* parent = nullptr);

   /**
    * @brief Возвращает док дерева.
    * @return left, right или bottom.
    */
   QString library_dock() const;

   /**
    * @brief Ставит дерево в док.
    * @param dock - left, right или bottom.
    */
   void set_library_dock(const QString& dock);

   /**
    * @brief Возвращает док таймлайна.
    * @return left, right или bottom.
    */
   QString timeline_dock() const;

   /**
    * @brief Ставит таймлайн в док.
    * @param dock - left, right или bottom.
    */
   void set_timeline_dock(const QString& dock);

   /**
    * @brief Возвращает док панели медиа.
    * @return left, right или bottom.
    */
   QString media_dock() const;

   /**
    * @brief Ставит медиа в док.
    * @param dock - left, right или bottom.
    */
   void set_media_dock(const QString& dock);

   /**
    * @brief Включён ли магнит таймлайна.
    * @return true, если края липнут.
    */
   bool snap_enabled() const;

   /**
    * @brief Включает или выключает магнит.
    * @param enabled - новое значение.
    */
   void set_snap_enabled(bool enabled);

   /**
    * @brief Возвращает ширину левого дока.
    * @return ширина в пикселях.
    */
   int left_width() const;

   /**
    * @brief Запоминает ширину левого дока.
    * @param width - ширина в пикселях.
    */
   void set_left_width(int width);

   /**
    * @brief Возвращает ширину правого дока.
    * @return ширина в пикселях.
    */
   int right_width() const;

   /**
    * @brief Запоминает ширину правого дока.
    * @param width - ширина в пикселях.
    */
   void set_right_width(int width);

   /**
    * @brief Возвращает высоту нижнего дока.
    * @return высота в пикселях.
    */
   int bottom_height() const;

   /**
    * @brief Запоминает высоту нижнего дока.
    * @param height - высота в пикселях.
    */
   void set_bottom_height(int height);

   /**
    * @brief Сбрасывает раскладку к значениям по умолчанию.
    */
   Q_INVOKABLE void reset_layout();

 signals:
   /**
    * @brief Изменились размеры или положение панелей.
    */
   void layout_changed();

 private:
   QString read_dock(const char* key, const char* fallback) const;
   void write_dock(const char* key, const QString& dock);
   int read_size(const char* key, int fallback) const;
   void write_size(const char* key, int value, int min_value,
                   int max_value);
};
