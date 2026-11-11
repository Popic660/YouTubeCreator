---
name: cpp-code-style
description: Apply this project's C++20 style when writing or editing C or C++. Use for new code, refactors, headers, naming, and Doxygen comments.
---

# C++ code style

Стиль нового кода и осознанного рефакторинга. Стандарт языка — C++20.
Возможности новее C++20 не использовать, пока стандарт проекта не изменён.

Для нового кода предпочитай средства стандартной библиотеки до C++20
включительно, если они проще старых приёмов: `std::string_view`, `std::span`,
`std::optional`, ranges и `constexpr`. Не добавляй сторонние аналоги этих
средств без причины.

Имена и API — по [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html), с отклонениями из этого скилла. Не переформатируй и не модернизируй несвязанный код. Не запускай clang-format, сборку и тесты без отдельного подтверждения пользователя.

Если в репозитории появится `.clang-format`, для форматирования он главнее таблиц ниже.

## Общие правила

| Тема | Правило |
|------|---------|
| Язык кода | английский |
| Язык комментариев | русский или английский |
| Транслит в коде | запрещён |
| Закомментированный код | не оставлять; удалять, если пользователь явно не просил сохранить |
| TODO | `TODO: описание задачи` |
| Кодировка | UTF-8 без BOM, без табов |

## Форматирование

| Параметр | Значение |
|----------|----------|
| Отступ | 3 пробела |
| Строка | макс. 80 символов |
| Скобки | `{` на той же строке |
| Указатели и ссылки | `int* ptr`, `int& ref` |
| Пробелы в условиях | `if (a == b)`, `for (int i = 0; i < n; ++i)` |
| Фигурные скобки | всегда, даже для одной строки |
| Тернарный оператор | только для простой логики; иначе `if` |

## Именование

| Сущность | Форма | Пример |
|----------|--------|--------|
| Класс | `C` + PascalCase | `CDeviceManager` |
| Структура | PascalCase | `EndpointInfo` |
| Метод / функция | snake_case | `register_device`, `load_config` |
| Локальная переменная | snake_case | `device_count` |
| Поле класса | snake_case + `_` | `device_count_` |
| Параметр | snake_case | `device_id` |
| Константа / constexpr | `k` + PascalCase | `kMaxBufferSize` |
| enum class | PascalCase | `DeviceState` |
| Значение enum | `k` + PascalCase | `kIdle` |
| Пространство имён | PascalCase | `DeviceUtils` |
| typedef / using | PascalCase | `DeviceId` |
| Макрос | ALL_UPPER | `ENABLE_TRACE` |
| Шаблонный параметр | PascalCase | `typename ValueType` |

Исключения: счётчики `i`, `j`, `k`, `index`; `it` в коротком range-for.

Целые фиксированной ширины бери из `<cstdint>`: `std::uint32_t`, `std::uint16_t` и соседние типы.

## Заголовочные файлы

| Правило | Требование |
|---------|------------|
| Include guard | `#pragma once`, не `#ifndef` |
| Forward declaration | предпочитать, чтобы уменьшить связность |
| Порядок `#include` | свой `.h`, затем проект (`"..."`), затем системные (`<...>`) |
| Группы инклудов | разделять пустой строкой |
| `using namespace` | запрещён в глобальной области и в `.h`, и в `.cpp` |

`using`-объявление (`using std::vector;`) предпочтительнее директивы. В заголовке — только внутри namespace. Локальный `using namespace` в теле функции допустим для узкого вспомогательного namespace, например `std::chrono_literals`, если без него код нечитаем. Широкие namespace (`std` и корни проекта) не открывать даже локально, если хватает полного имени или `using`-объявления.

```cpp
#pragma once

#include "peer_service.h"

#include <string>
#include <vector>

class COtherManager;

/**
 * @brief Описание.
 */
class CDeviceManager {
 public:
  void register_device(std::uint32_t device_id);

 private:
  std::uint32_t device_count_ = 0;
};
```

## Классы и структуры

Порядок секций:

1. `public`: конструкторы и деструктор
2. `public`: методы
3. `protected`: методы
4. `protected`: поля отдельной секцией
5. `private`: методы
6. `private`: поля

| Практика | Правило |
|----------|---------|
| `explicit` | любой конструктор с параметрами; без него только копирование, перемещение или явно оправданный случай |
| `override` | на переопределении виртуального метода |
| `final` | где наследование не нужно |
| `= default` / `= delete` | вместо пустых тел |
| Виртуальный деструктор | у любого класса, от которого наследуют |
| Константы | `static constexpr` и имена `k…`, не `#define` |
| Короткий inline | одна-две строки, в классе в `.h` |

```cpp
class CDeviceManager {
 public:
  CDeviceManager() = default;
  explicit CDeviceManager(std::uint32_t initial_capacity);
  virtual ~CDeviceManager();

  void register_device(std::uint32_t device_id);
  std::uint32_t get_count() const { return device_count_; }

 protected:
  void on_device_added(std::uint32_t device_id);

 private:
  std::uint32_t device_count_ = 0;
};
```

Структура без префикса `C`:

```cpp
struct EndpointInfo {
  std::string host;
  std::uint16_t port = 0;
};
```

## Современный C++

| Вместо | Использовать |
|--------|--------------|
| `NULL` | `nullptr` |
| C-style cast | `static_cast` / `reinterpret_cast` |
| `enum Foo { … }` | `enum class` с базовым типом и значениями `k…` |
| сырые `new` / `delete` | `std::unique_ptr` / `std::shared_ptr` |
| невладеющая строка | `std::string_view` |
| невладеющий непрерывный диапазон | `std::span` |
| `#define CONST` | `static constexpr` или `constexpr` |
| глобальные переменные | namespace, минимум таких объектов, имя `snake_case` |

```cpp
enum class DeviceState : std::uint8_t {
  kIdle,
  kRunning,
};
```

### Параметры и результат

Объекты, от предпочтительного к менее предпочтительному. Указатель нужен только с причиной:

1. `const T&` — вход, объект не меняется
2. `T&` — выход или in-out
3. `std::optional<T>` — значение может отсутствовать
4. `std::shared_ptr<T>` — совместное владение
5. `const T*` — опциональный вход (`nullptr`)
6. `T*` — опциональный выход или in-out

Примитивы (`std::uint32_t`, `bool` и аналоги) передавай по значению.

Результат — массив, список или объект — предпочтительно возвращать (`std::vector<T>`, `bool`, `std::optional<T>`). Выходной параметр только если это оправдано: переиспользование буфера, невозможность копирования или уже существующий API. Префикс `out_` не обязателен; имя должно показывать роль.

```cpp
bool load_devices(const std::string& path,
                  std::vector<CDevice>& out_devices);
```

### Итерация

От предпочтительного к менее предпочтительному:

1. алгоритм стандартной библиотеки, включая ranges C++20, если он закрывает задачу
2. `std::for_each`, если операция применяется ко всем элементам
3. range-based for, если нужен ранний выход или `std::for_each` не подходит
4. индексный `for` и `while` только с причиной

```cpp
if (device_id == 0) {
  return false;
}

for (const auto& device : devices_) {
  process(device);
}
```

### Пространства имён

Новый самостоятельный модуль оборачивай в namespace `PascalCase`:

```cpp
namespace DeviceUtils {

bool validate_id(std::uint32_t device_id);

}  // namespace DeviceUtils
```

## Комментарии

Новый код документируй только Doxygen-блоком `/** … */` со `*` в начале каждой строки. Блок `/* … */` без второй звёздочки не использовать. При правке существующего объявления переведи его комментарий на Doxygen; чужие комментарии массово не переписывай.

| Назначение | Формат |
|------------|--------|
| Класс, struct, enum | `/** */` и `@brief` |
| Метод, функция, конструктор | `/** */`, `@brief`, `@param`, `@return` |
| Короткая ремарка в теле | `//` с пробелом и заглавной буквы |
| Деструктор | можно без комментария |

Обязательные теги:

1. `@brief` — у типов и функций.
2. `@param` — у каждого параметра, после имени дефис: `@param device_id - описание`.
3. `@return` — если функция не `void`.
4. `@code` / `@endcode` — по необходимости, для примера вызова.

Обязательно комментируй класс, struct, enum и публичные функции. Желательно комментировать нетривиальное тело длиннее 10 строк. Деструктор и очевидный геттер вроде `get_count()` можно не комментировать.

```cpp
/**
 * @brief Зарегистрировать устройство по id.
 * @param device_id - уникальный идентификатор
 * @return true, если устройство было добавлено
 */
bool register_device(std::uint32_t device_id);
```

```cpp
// Пропускаем невалидные id.
if (device_id == 0) {
  return false;
}
```
