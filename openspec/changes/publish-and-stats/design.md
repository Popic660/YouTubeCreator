# Design

## Context

См. proposal.md — Why. Требования — в `specs/publish`, `analytics`, `library`, `main-window`, `channels`.

Сейчас `library.db` — `user_version` 6, таблица `channels(channel_id, title)`, публикаций нет. `CChannelAuth` пишет refresh в DPAPI и не хранит access. `CHttpTransport` умеет GET и POST без PUT и без чужих заголовков. `CExporter` пишет `exports/<id>.mp4` 1080×1920. Обложка — `shorts/<id>/youtube_cover.jpg`. Статус ролика после конвейера — `ready`. В шапке залитая «Экспорт», hint каналов говорит, что публикация не запускается. `FrameView.centerMode` — `empty` или `preview`. `Theme.plot` уже `#3f3f3f`.

## Goals / Non-Goals

**Goals:**

- Resumable upload и Analytics за заглушкой транспорта, без живого Google в `shell_tests`.
- Access-токен только в памяти, квота только локальный счётчик.
- Экран аналитики в центре без нового дока и без Qt Charts.

**Non-Goals:**

- Запрос остатка квоты у Google Cloud Monitoring.
- Chunked upload с докачкой после обрыва посередине файла (один PUT на файл).
- UI «сделано для детей» и выбор категории YouTube.
- Повторный OAuth ради новых scopes.

## Decisions

### Оркестраторы рядом с `CChannelAuth`, не вызовы из QML

`CChannelAuth` получает `access_token(channel_id)`: `POST oauth2.googleapis.com/token` с `grant_type=refresh_token`, кэш access в памяти до `expires_in`. На диск не писать. Если refresh нет или обмен падает — ошибка, канал не отключать.

Новые типы:

- `CPublisher` — проверки, resumable insert, обложка, строки публикаций, локальная квота.
- `CStatsSync` — Data API и Analytics API, запись снимка.

Рассматривался один `CYoutubeClient` на всё. Тогда прогресс загрузки и снимок статистики делили бы один объект с каналами. Как у конвейера: оркестратор шага отдельно от входа.

Тест: `use_stub()` на транспорте и на auth. `complete_with_code` уже есть; для refresh заглушка отдаёт JSON access. Живого Google нет.

### Resumable insert, не multipart одним POST

Порядок на канал:

1. Проверки: файл `exports/<id>.mp4` есть, ширина < высоты (экспорт 1080×1920), `duration_ms <= 180000`.
2. `access_token`.
3. `POST https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status` с JSON названия, описания и `privacyStatus`. Заголовки `X-Upload-Content-Type: video/mp4` и `X-Upload-Content-Length`.
4. `PUT` на `Location` телом файла.
5. Id из JSON. Статус публикации `uploaded`.
6. Если есть `cover_relpath` — `POST thumbnails/set`. Успех — `cover_status = set`. HTTP 403 / «custom thumbnail» — публикация успешна, `cover_status = skipped`. Другая ошибка обложки — `cover_status = failed`, видео не откатывать.

Название в запросе — поле диалога, по умолчанию имя ролика, обрезка до 100 символов. Описание — поле диалога, по умолчанию сценарий. Приватность: `private` / `unlisted` / `public`. `selfDeclaredMadeForKids: false` без отдельного контрола: ТЗ его не просит, API без поля отклоняет insert.

Рассматривался multipart `uploadType=media`. Прогресс байт и повтор с Location тогда хуже стыкуются с заглушкой заголовков.

Каналы в диалоге обрабатываются по очереди. Ошибка одного не прерывает цикл.

### Транспорт: PUT и заголовки ответа

`CHttpTransport::post` и новый `put` принимают карту сырых заголовков. `HttpResponse` дополняется `location` (и при необходимости другими). Заглушка: `enqueue_json` как сейчас; для resumable — JSON с полем или отдельный `enqueue_json` плюс URL в теле, а Location в тесте задаётся через очередь заголовков (`enqueue_header("Location", url)`). `googleCount` уже считает `googleapis.com/youtube` и `oauth2.googleapis.com`; Analytics — `youtubeanalytics.googleapis.com`, его тоже включить в тот же счётчик.

Прогресс PUT: сигнал `uploadProgress` у живого `QNetworkReply`. В заглушке сразу 100%. Диалог показывает процент канала; это не красный прогресс превью.

Рассматривался Qt Network Auth / `QHttpMultiPart` только для обложки. Обложка — отдельный POST байт JPEG с Bearer, без нового модуля.

### Квота — локальный счётчик ведра insert

YouTube не отдаёт остаток квоты клиенту. С 1 июня 2026 `videos.insert` — своё ведро: 100 вызовов в сутки, 1 единица. Общие 10 000 — на `thumbnails.set` (50), `videos.list` (1), `channels.list` (1) и Analytics. В диалоге показываем остаток выгрузок: `100 - insert_count` за текущие сутки по тихоокеанскому календарю (`America/Los_Angeles`, сброс в полночь PT).

Таблица `quota_usage(day_pt TEXT PRIMARY KEY, insert_count INTEGER)`. Счётчик растёт после вызова insert (в том числе ошибочного, если запрос ушёл). `thumbnails.set` в это ведро не входит и в сообщении квоты не вычитается.

ТЗ правим под эти цифры. Старые «1 600 единиц, около шести выгрузок» убираем.

Рассматривался Cloud Monitoring. Нужен другой OAuth и проектный ключ — вне ТЗ.

### Схема `6 → 7`

```
CREATE TABLE publications (
  id TEXT PRIMARY KEY,
  short_id TEXT NOT NULL,
  channel_id TEXT NOT NULL,
  video_id TEXT NOT NULL DEFAULT '',
  privacy TEXT NOT NULL,
  status TEXT NOT NULL,
  cover_status TEXT NOT NULL DEFAULT '',
  error TEXT NOT NULL DEFAULT '',
  uploaded_ms INTEGER NOT NULL DEFAULT 0,
  UNIQUE(short_id, channel_id)
)

CREATE TABLE stats_snapshots (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  target_id TEXT NOT NULL,
  synced_ms INTEGER NOT NULL,
  payload TEXT NOT NULL
)

CREATE TABLE quota_usage (
  day_pt TEXT PRIMARY KEY,
  insert_count INTEGER NOT NULL DEFAULT 0
)
```

`PRAGMA user_version = 7`. Папки, ролики, каналы, задачи не трогать. Повтор публикации на тот же канал обновляет строку, вторую не создаёт.

`payload` снимка — JSON счётчиков и точек графика. Поиск по `payload` не добавлять.

Отключение канала: `remove_channel` + `clear_channel_refresh`, строки `publications` и снимки канала остаются. Синхронизация без refresh не ходит в сеть.

Статус ролика `published`, если есть хотя бы одна публикация со статусом успеха (`uploaded` / `done` с непустым `video_id`). Конвейер по-прежнему ставит `ready` и не ставит `published`.

### UI: шапка, диалог, центр

`HeaderBar`: залитая `publishButton` «Опубликовать», `exportButton` с `filled: false`. Выключена без выбранного ролика. Hint каналов без фразы «публикация не запускается».

Диалог как остальные: фон `#282828`, поля радиус 4px, залитое подтверждение, тональная отмена. Чекбоксы каналов, чипы приватности. Строка квоты вторичным текстом. После старта — список каналов со статусом и прогрессом.

Аналитика — `AnalyticsView.qml` вместо `FrameView` в центре, не док. `centerMode` оболочки: `empty` / `preview` / `analytics`. Таймлайн `visible: centerMode !== "analytics"`. Дерево не трогаем.

Вход:

- Название канала в меню шапки → `analyticsKind = channel`, `analyticsId = channel_id`. Выбор ролика сбрасывается, «Опубликовать» серая.
- Пункт «Статистика» в `shortMenu`, если есть `video_id` → `analyticsKind = video`. Тот же ролик остаётся выбранным.
- Клик по ролику в дереве во время аналитики возвращает кадр и таймлайн.

Периоды чипами: 7 / 28 / 90 дней. Выбранный — залитый чип. График — `Canvas` линия на фоне `Theme.plot`, оси `textSecondary`. Qt Charts не подключаем: лишний модуль ради одной серии.

Кнопка «Обновить» на экране запускает `CStatsSync`. Пока снимка нет — вторичный текст, сети нет.

### Analytics: два API, явная кнопка

Ролик:

1. `videos.list?part=statistics&id=` — viewCount, likeCount, commentCount.
2. `youtubeanalytics.googleapis.com/v2/reports` с `ids=channel==`, `filters=video==`, `dimensions=day`, метрики `views,estimatedMinutesWatched,averageViewDuration,likes,impressions,impressionClickThroughRate`.

Канал: `channels.list?part=statistics` (subscriberCount, viewCount) плюс тот же reports без `filters=video`.

Если в строке отчёта нет `impressions` или CTR — ячейка «нет в этом канале», остальные метрики рисуем. Под графиком фиксированная подпись про задержку до двух суток.

Рассматривался только Data API. ТЗ требует период и время просмотра — это Analytics API, scope уже выдан на этапе 9.

## Risks / Trade-offs

- [Квота в диалоге не совпадает с Console] → подпись, что это локальный счёт выгрузок приложения; 403 `quotaExceeded` показывает ошибку канала и не откатывает другие.
- [Brand / custom thumbnail запрещён] → публикация без обложки, статус `skipped`, видео на месте.
- [Refresh протух] → ошибка канала, повторный вход из меню; список каналов не чистим сами.
- [Сценарий-JSON в описании] → пользователь правит поле в диалоге; по умолчанию сырой `script`.
- [Один PUT без докачки] → обрыв = ошибка этого канала, повтор — новый insert. Файлы Shorts небольшие.

## Migration Plan

При `open` версии 6: три таблицы, `user_version = 7`. Старый exe базу v7 не открывает, как у 5 → 6. Публикаций нет — статусы роликов как были. Счётчик квоты пустой. DPAPI не меняется.

## Open Questions

Нет. Квота-счётчик, resumable PUT, статус выложен после первого успеха, вход в аналитику из меню канала и пункта ролика зафиксированы выше.
