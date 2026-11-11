#include "window_state.h"

#include <QGuiApplication>
#include <QIcon>
#include <QQuickWindow>
#include <QScreen>
#include <QSettings>

#include <algorithm>

namespace {

constexpr int kDefaultWidth = 1280;
constexpr int kDefaultHeight = 800;
constexpr char kIconPath[] = ":/icons/window-icon.png";

/**
 * @brief Проверяет, что прямоугольник виден хотя бы на одном экране.
 * @param rect - положение и размер окна.
 * @return true, если прямоугольник пересекает экран.
 */
bool on_any_screen(const QRect& rect) {
   const QList<QScreen*> screens = QGuiApplication::screens();
   for (QScreen* screen : screens) {
      if (screen == nullptr) {
         continue;
      }
      if (screen->availableGeometry().intersects(rect)) {
         return true;
      }
   }
   return false;
}

/**
 * @brief Ставит окно в видимую область в размере по умолчанию.
 * @param window - главное окно.
 */
void place_visible_default(QQuickWindow* window) {
   QScreen* screen = window->screen();
   if (screen == nullptr) {
      screen = QGuiApplication::primaryScreen();
   }
   if (screen == nullptr) {
      window->resize(kDefaultWidth, kDefaultHeight);
      window->setPosition(0, 0);
      return;
   }
   const QRect area = screen->availableGeometry();
   const int width = std::min(kDefaultWidth, area.width());
   const int height = std::min(kDefaultHeight, area.height());
   window->resize(width, height);
   window->setPosition(area.x(), area.y());
}

/**
 * @brief Приводит объект QML к окну.
 * @param object - объект из QML.
 * @return окно или nullptr.
 */
QQuickWindow* as_window(QObject* object) {
   return qobject_cast<QQuickWindow*>(object);
}

}  // namespace

CWindowState::CWindowState(QObject* parent) : QObject(parent) {}

bool CWindowState::apply_icon(QObject* window) {
   QQuickWindow* quick = as_window(window);
   if (quick == nullptr) {
      return false;
   }
   const QIcon icon(QString::fromLatin1(kIconPath));
   if (icon.isNull()) {
      return false;
   }
   quick->setIcon(icon);
   return true;
}

void CWindowState::save_geometry(QObject* window) {
   QQuickWindow* quick = as_window(window);
   if (quick == nullptr) {
      return;
   }
   QSettings settings;
   settings.setValue("window/x", quick->x());
   settings.setValue("window/y", quick->y());
   settings.setValue("window/width", quick->width());
   settings.setValue("window/height", quick->height());
}

void CWindowState::restore_geometry(QObject* window) {
   QQuickWindow* quick = as_window(window);
   if (quick == nullptr) {
      return;
   }
   QSettings settings;
   if (!settings.contains("window/width")) {
      return;
   }
   const QRect rect(settings.value("window/x").toInt(),
                    settings.value("window/y").toInt(),
                    settings.value("window/width").toInt(),
                    settings.value("window/height").toInt());
   if (!on_any_screen(rect)) {
      place_visible_default(quick);
      return;
   }
   quick->setGeometry(rect);
}
