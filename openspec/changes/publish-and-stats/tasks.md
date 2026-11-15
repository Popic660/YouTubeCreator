# Tasks

## 1. Квота в ТЗ

- [x] 1.1 В `docs/tz.md` заменить старые «10 000 единиц, вставка ≈ 1 600, около шести выгрузок» на актуальные: отдельное ведро 100 вызовов `videos.insert` в сутки (1 единица), общий пул 10 000 на остальные методы, остаток в диалоге — локальный счётчик, сброс в полночь PT. Предел 180 секунд не трогать. Проверка: в ТЗ нет «1 600» и «шести выгрузок»; есть 100 вызовов insert и 180 секунд.

## 2. Схема библиотеки

- [x] 2.1 Сначала в `tests/tst_library.qml` открыть базу `user_version` 6 с папкой, черновиком и каналом (фикстура `CTempDirectory`, если нужна). Затем в `CLibraryStore` мигрировать на `user_version` 7: таблицы `publications`, `stats_snapshots`, `quota_usage`. Прежние тесты, что ждут версию 6, перевести на 7. Проверка: тест видит версию 7, прежние папки, ролики и каналы, `schema_contains("publications")`, публикаций 0.

- [x] 2.2 `upsert` публикации пишет `short_id`, `channel_id`, `video_id`, приватность и статус; повтор той же пары обновляет строку. После `open` поля на месте, в sqlite нет токена. Проверка: `tst_library.qml` два вызова с одним каналом — одна строка и новый `video_id`; содержимое `library.db` не содержит подставленный refresh.

- [x] 2.3 Две публикации на разные каналы переживают `open`. Отключение канала снимает строку `channels` и токен, публикации остаются. Проверка: `tst_library.qml` после `disconnect_channel` — `channel_count` 0, `video_id` публикаций на месте, `googleCount` не растёт.

- [x] 2.4 Снимок статистики пишется JSON `payload` и `synced_ms`; после `open` те же цифры. Поиск по тексту payload даёт «Ничего не найдено». Проверка: `tst_library.qml` повторный `open` читает счётчики; поиск уникального фрагмента payload показывает `notFoundMessage`.

- [x] 2.5 `quota_usage` считает insert за сутки PT: остаток `100 - insert_count`. После исчерпания остаток 0. Проверка: `tst_library.qml` после 100 инкрементов `quota_remaining` 0; запрос к Google из этого теста не идёт.

## 3. Транспорт загрузки

- [x] 3.1 Сначала в `tst_pipeline.qml` через `use_stub` положить ответ с заголовком `Location` и вызвать PUT. Затем `CHttpTransport`: `put`, сырые заголовки на POST/PUT, `HttpResponse.location`, `enqueue_header`, `googleCount` для `youtubeanalytics.googleapis.com`. Проверка: тест читает URL PUT и Location; `googleCount` растёт на analytics-хост; chat/kling не растут; сеть не вызывается.

## 4. Access-токен

- [x] 4.1 Сначала в `tst_pipeline.qml` задать refresh канала и JSON access. Затем `CChannelAuth::access_token` делает form POST `grant_type=refresh_token` и держит access в памяти. Проверка: метод возвращает access; после `save` в `library.db` и `project.json` строки access нет; `googleCount` 1.

- [x] 4.2 Без refresh или при ошибке обмена access пустой, канал не удаляется. Проверка: `tst_pipeline.qml` — `channel_count` прежний, транспорт при пустом refresh не вызывался.

## 5. Публикация по заглушке

- [x] 5.1 `CPublisher` в `src/publisher.h/.cpp` (подключить в `CMakeLists.txt`). Без файла `exports/<id>.mp4` или при `duration_ms > 180000` загрузка не стартует, в `lastError` причина. Проверка: `tst_pipeline.qml` / `tst_library.qml` — `googleCount` 0, публикаций нет, текст ошибки про экспорт или длительность.

- [x] 5.2 Заглушка: refresh → access, resumable POST с Location, PUT, JSON с `id`. Пишется публикация, статус ролика `published`. Проверка: `tst_pipeline.qml` видит `video_id`, `short_status` `published`, в `urls` есть `upload/youtube/v3/videos` и PUT; `openUrl` не вызывался.

- [x] 5.3 Два канала: первый `enqueue_error`, второй успешный JSON. Проверка: у первого статус ошибки, у второго `video_id`, ролик `published`, цикл не оборван после первого сбоя.

- [x] 5.4 Обложка: успешный `thumbnails/set` ставит `cover_status` `set`. HTTP 403 про thumbnail — публикация успешна, `cover_status` `skipped`. Проверка: два случая в `tst_pipeline.qml`; `video_id` в обоих на месте.

- [x] 5.5 При `quota_remaining` 0 insert не вызывается. Проверка: `tst_pipeline.qml` — ошибка про квоту, `googleCount` без videos.insert.

## 6. Кнопка и диалог

- [x] 6.1 В `HeaderBar.qml` залитая `publishButton` «Опубликовать», `exportButton` с `filled: false`. Без выбранного ролика кнопка выключена. Hint каналов не содержит, что публикация не запускается. Проверка: `tst_shell.qml` — `publishButton.filled` true, `exportButton.filled` false, без ролика `enabled` false; `channelHint` без этой фразы.

- [x] 6.2 Диалог публикации: название = имя ролика, описание = сценарий, чекбоксы каналов, чипы приватности, строка остатка квоты. Фон `#282828`, поле радиус 4px, залитое подтверждение. Проверка: `tst_shell.qml` / `tst_library.qml` после выбора ролика с каналом открывает диалог и читает поля по `objectName`.

- [x] 6.3 Подтверждение без отмеченных каналов не зовёт транспорт. После stub-публикации в диалоге виден статус канала. Проверка: `tst_library.qml` — `googleCount` 0 без галок; с галкой и заглушкой виден `video_id`.

## 7. Синхронизация статистики

- [x] 7.1 `CStatsSync` в `src/stats_sync.h/.cpp` (подключить в `CMakeLists.txt`). Заглушка `videos.list` / `channels.list` и reports. Вызов `refresh` пишет снимок. Без `refresh` сети нет. Проверка: `tst_pipeline.qml` после `refresh` видит просмотры и `synced_ms`; до вызова `googleCount` прежний.

- [x] 7.2 Отчёт без impressions/CTR даёт в payload признак «нет в этом канале»; остальные метрики пишутся. Без refresh-токена `refresh` не ходит в сеть, старый снимок остаётся. Проверка: два случая в `tst_pipeline.qml` / `tst_library.qml`.

## 8. Экран аналитики

- [x] 8.1 `AnalyticsView.qml`: поле графика `Theme.plot` `#3f3f3f`, чипы 7/28/90, подпись про задержку до двух суток, кнопка «Обновить». В `Main.qml` режим `analytics` скрывает таймлайн, дерево на месте. Проверка: `tst_shell.qml` — `analyticsView` виден, `timelineHost.visible` false, `libraryList` на месте, `plotSurface.color` `#3f3f3f`.

- [x] 8.2 Клик названия канала в меню открывает экран канала, выбор ролика сбрасывается. Пункт `menuStats` в `shortMenu` открывает экран ролика только если есть `video_id`. Клик ролика в дереве возвращает кадр и таймлайн. Проверка: `tst_library.qml` — канал → `centerMode` analytics; черновик не открывает экран; после клика ролика таймлайн снова виден.

## 9. Сборка

- [x] 9.1 Прогнать `build.bat` до `shell_tests`. Проверка: код выхода 0, `youtube-creator.exe` и `shell_tests` собраны; в изменении нет живого `videos.insert` и Analytics из тестов.

## Workflow follow-up

- Архивация change — после ревью и явного запроса, не в этом apply.
- Реализация — `/opsx-apply`, не из propose.
