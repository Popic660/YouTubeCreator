#include "dock_state.h"

#include <QSettings>

namespace {

constexpr int kDefaultSide = 240;
constexpr int kDefaultBottom = 200;
constexpr int kMinSide = 160;
constexpr int kMaxSide = 640;
constexpr int kMinBottom = 80;
constexpr int kMaxBottom = 480;

/**
 * @brief Оставляет только известное имя дока.
 * @param dock - введённое имя.
 * @return left, right, bottom или пустая строка.
 */
QString known_dock(const QString& dock) {
   if (dock == QStringLiteral("left") ||
       dock == QStringLiteral("right") ||
       dock == QStringLiteral("bottom")) {
      return dock;
   }
   return {};
}

}  // namespace

CDockState::CDockState(QObject* parent) : QObject(parent) {}

QString CDockState::library_dock() const {
   return read_dock("layout/libraryDock", "right");
}

void CDockState::set_library_dock(const QString& dock) {
   write_dock("layout/libraryDock", dock);
}

QString CDockState::timeline_dock() const {
   return read_dock("layout/timelineDock", "bottom");
}

void CDockState::set_timeline_dock(const QString& dock) {
   write_dock("layout/timelineDock", dock);
}

int CDockState::left_width() const {
   return read_size("layout/leftWidth", kDefaultSide);
}

void CDockState::set_left_width(int width) {
   write_size("layout/leftWidth", width, kMinSide, kMaxSide);
}

int CDockState::right_width() const {
   return read_size("layout/rightWidth", kDefaultSide);
}

void CDockState::set_right_width(int width) {
   write_size("layout/rightWidth", width, kMinSide, kMaxSide);
}

int CDockState::bottom_height() const {
   return read_size("layout/bottomHeight", kDefaultBottom);
}

void CDockState::set_bottom_height(int height) {
   write_size("layout/bottomHeight", height, kMinBottom, kMaxBottom);
}

void CDockState::reset_layout() {
   QSettings settings;
   settings.remove(QStringLiteral("layout/libraryDock"));
   settings.remove(QStringLiteral("layout/timelineDock"));
   settings.remove(QStringLiteral("layout/leftWidth"));
   settings.remove(QStringLiteral("layout/rightWidth"));
   settings.remove(QStringLiteral("layout/bottomHeight"));
   settings.sync();
   emit layout_changed();
}

QString CDockState::read_dock(const char* key,
                              const char* fallback) const {
   QSettings settings;
   const QString value =
       settings.value(QString::fromLatin1(key)).toString();
   const QString known = known_dock(value);
   if (!known.isEmpty()) {
      return known;
   }
   return QString::fromLatin1(fallback);
}

void CDockState::write_dock(const char* key, const QString& dock) {
   const QString known = known_dock(dock);
   if (known.isEmpty() || known == read_dock(key, "")) {
      return;
   }
   QSettings settings;
   settings.setValue(QString::fromLatin1(key), known);
   settings.sync();
   emit layout_changed();
}

int CDockState::read_size(const char* key, int fallback) const {
   QSettings settings;
   const QString name = QString::fromLatin1(key);
   if (!settings.contains(name)) {
      return fallback;
   }
   return settings.value(name).toInt();
}

void CDockState::write_size(const char* key, int value, int min_value,
                            int max_value) {
   int clamped = value;
   if (clamped < min_value) {
      clamped = min_value;
   }
   if (clamped > max_value) {
      clamped = max_value;
   }
   if (clamped == read_size(key, clamped + 1)) {
      return;
   }
   QSettings settings;
   settings.setValue(QString::fromLatin1(key), clamped);
   settings.sync();
   emit layout_changed();
}
