# Tasks

## 1. Клиент Google в DPAPI

- [x] 1.1 Сначала в `tests/tst_pipeline.qml` сохранить `googleClientId` и секрет через память `CSecretStore`. Затем расширить JSON DPAPI полями `google_client_id`, `google_client_secret` и объектом `channel_tokens`. Проверка: после `save` строк секрета и токена нет в `library.db` и в `project.json`; `hasGoogleClient` true, поле секрета пустое; `hasKey` чата не меняется.

- [x] 1.2 Повторное `load` отдаёт тот же client id и `hasGoogleClient` без открытого секрета. Пустая карта токенов читается как отсутствие каналов. Проверка: `tst_pipeline.qml` после нового объекта хранилища видит id и `hasGoogleClient`; `channel_refresh` для неизвестного id пустой.

## 2. Схема каналов

- [x] 2.1 Сначала в `tests/tst_library.qml` открыть базу `user_version` 5 с папкой и черновиком. Затем в `CLibraryStore` мигрировать на `user_version` 6: таблица `channels` (`channel_id`, `title`). Проверка: тест видит версию 6, прежние папки и ролики, `channel_count` 0, `schema_contains("channels")`.

- [x] 2.2 `upsert_channel` пишет id и название; повтор того же id обновляет название и не плодит строку. После `open` оба поля на месте. Проверка: `tst_library.qml` два вызова с одним id — `channel_count` 1 и новое название.

- [x] 2.3 Два разных канала переживают `open`. Поиск по названию канала даёт «Ничего не найдено». В sqlite нет refresh-токена. Проверка: `tst_library.qml` после повторного `open` видит два id; поиск фрагмента title даёт `notFoundMessage`; содержимое `library.db` не содержит подставленный токен.

## 3. Транспорт Google

- [x] 3.1 Сначала в `tst_pipeline.qml` через `use_stub` положить JSON токена и вызвать POST с content-type `application/x-www-form-urlencoded`. Затем `CHttpTransport::post` принимает тип тела (JSON по умолчанию) и считает `googleCount` для `oauth2.googleapis.com` и `googleapis.com/youtube`. Проверка: тест читает URL и тело form; `googleCount` растёт; chat/kling счётчики не растут; сеть не вызывается.

## 4. Вход по заглушке

- [x] 4.1 `CChannelAuth` в `src/channel_auth.h/.cpp` (подключить в `CMakeLists.txt`): при `use_stub` метод `complete_with_code` не открывает браузер. Заглушка отдаёт JSON токена с `refresh_token` и JSON `channels.list` с одним item. Проверка: `tst_pipeline.qml` / `tst_library.qml` видят канал в store, `has_channel_refresh`, `googleCount` 2, в `urls` есть `oauth2.googleapis.com/token` и `youtube/v3/channels`; `openUrl` не вызывался.

- [x] 4.2 Без refresh_token в ответе канал не пишется. Проверка: `tst_pipeline.qml` — `channel_count` прежний, токена нет.

- [x] 4.3 Ошибка token или `channels.list` не добавляет канал. Проверка: два случая `enqueue_error` в `tst_pipeline.qml`.

- [x] 4.4 `complete_with_error` (отмена) не меняет список. Проверка: после подключённого канала отмена второго входа оставляет `channel_count` 1.

- [x] 4.5 Без открытой библиотеки или без `hasGoogleClient` `start` не зовёт транспорт и не открывает браузер. Проверка: `googleCount` 0 в обоих случаях в `tst_library.qml`.

- [x] 4.6 Второй канал с другим id появляется рядом. Повтор того же id оставляет одну строку и обновляет название и токен. Проверка: `tst_library.qml` — два id; затем повтор первого — `channel_count` 2, title первого новый.

## 5. Отключение

- [x] 5.1 `disconnect_channel` удаляет строку sqlite и ключ токена в `CSecretStore`. Второй канал остаётся. Запроса к YouTube нет. Проверка: `tst_library.qml` после отключения одного из двух — `channel_count` 1, `has_channel_refresh` ложь для удалённого, `googleCount` не растёт.

## 6. Меню и настройки

- [x] 6.1 Кнопка `channelMenuButton` открывает меню фон `#282828`. Есть пункт «Подключить канал». Поля вставки ссылки канала нет. Пока каналов нет, строк каналов нет. Проверка: `tst_shell.qml` клик открывает `channelMenu`; `channelMenuSurface.color` `#282828`; `connectChannelItem` виден.

- [x] 6.2 После stub-входа в меню видны названия. `channelConnected` true. Hint кнопки не содержит «заглушка». Проверка: `tst_shell.qml` / `tst_library.qml` находят пункты по `objectName`; `test_brandAndChannels` больше не ждёт вечный `false` после клика без входа — без клиента `channelConnected` остаётся false.

- [x] 6.3 В диалоге настроек — поля client id и секрета Google. Фон `#282828`, поле радиус 4px, кнопка-капсула. После сохранения секрет не в подписи поля. Проверка: `tst_shell.qml` после `settingsSave` видит `hasGoogleClient` и пустой `settingsGoogleSecretField`.

- [x] 6.4 Из меню можно отключить канал. Проверка: `tst_library.qml` клик отключения убирает пункт канала и ставит `channelConnected` false, если каналов не осталось.

## 7. Сборка

- [x] 7.1 Прогнать `build.bat` до `shell_tests`. Проверка: код выхода 0, `youtube-creator.exe` и `shell_tests` собраны; в изменении нет живого входа Google, `videos.insert` и запросов Analytics API из тестов.

## Workflow follow-up

- Архивация change — после ревью и явного запроса, не в этом apply.
- Реализация — `/opsx-apply`, не из propose.
