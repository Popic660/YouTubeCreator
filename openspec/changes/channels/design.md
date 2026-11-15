# Design

## Context

См. proposal.md — Why. Требования — в `specs/channels`, `library`, `main-window`.

Сейчас `library.db` — `user_version` 5, таблиц каналов нет. `CSecretStore` держит ключи чата и Kling в одном DPAPI JSON. `CHttpTransport` умеет POST JSON и GET с Bearer. В `HeaderBar` кнопка `channelMenuButton` с пустым `onClicked`; `Main.qml` отдаёт `channelConnected: false`. Тест `test_brandAndChannels` ждёт, что клик канал не подключает.

## Goals / Non-Goals

**Goals:**

- Loopback OAuth и запись канала без живого Google в `shell_tests`.
- Токены рядом с ключами моделей, не в sqlite.
- Меню шапки по гайду, без новой док-панели.

**Non-Goals:**

- Свой Google Cloud проект в репозитории и зашитый client id.
- Custom URI scheme (`youtube-creator://`).
- Вызов videos.insert и Analytics API.

## Decisions

### Клиент OAuth задаёт пользователь, не приложение

Client id и client secret Google лежат в том же DPAPI JSON, что Kling: поля `google_client_id`, `google_client_secret`. Поле секрета после `save` пустое, `hasGoogleClient` отдельно от `hasKey`. Без id вход не стартует: как без ключа Kling не стартует видео.

Рассматривался зашитый client id приложения. Своего сервера нет, ключи моделей уже на стороне пользователя. Desktop-клиент в Google Cloud пользователь создаёт сам (тип «Приложение для компьютера», redirect `http://127.0.0.1`).

Рассматривался только client id без секрета (публичный клиент + PKCE). У типа Desktop у Google всё равно выдаётся секрет; храним оба, PKCE всё равно включаем.

### Loopback на эфемерном порту, не custom scheme

`CChannelAuth` поднимает `QTcpServer` на `127.0.0.1:0`, собирает `redirect_uri = http://127.0.0.1:<port>/`, открывает системный браузер через `QDesktopServices::openUrl`. После GET с `code` или `error` отвечает короткой HTML-страницей и закрывает слушатель.

PKCE S256, `access_type=offline`, `prompt=consent select_account`, `include_granted_scopes=true`. Scopes:

- `https://www.googleapis.com/auth/youtube.upload`
- `https://www.googleapis.com/auth/youtube.readonly`
- `https://www.googleapis.com/auth/yt-analytics.readonly`

Upload и analytics на этом этапе не вызываются: согласие один раз, чтобы этапы 10–11 не просили повторный вход.

Рассматривался фиксированный порт. Занятость порта ломает вход; эфемерный порт совпадает с ТЗ «локальный порт».

Нет поля «вставить ссылку канала»: меню только «Подключить канал» и отключение.

### Оркестратор `CChannelAuth`, не вызов из QML

Порядок живого входа:

1. Проверить открытую библиотеку и `hasGoogleClient`.
2. Стартовать loopback, открыть браузер.
3. `POST https://oauth2.googleapis.com/token` (`application/x-www-form-urlencoded`): code, client, PKCE verifier, redirect.
4. `GET https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true` с access token.
5. Взять первый item: `id`, `snippet.title`. Access token в память на этот вход, на диск не писать.
6. `CLibraryStore::upsert_channel(id, title)` и `CSecretStore::set_channel_refresh(id, refresh_token)` + `save`.

Повтор того же `channel_id`: обновить название и токен, вторую строку не создавать.

Отмена: `error=access_denied` или закрытие слушателя без кода — список не меняется. Ошибка token или `channels.list` — то же.

Отключение: `remove_channel` в sqlite и удаление ключа токена в DPAPI. Запросов к YouTube нет.

Рассматривался `QOAuth2AuthorizationCodeFlow`. Он тянет Qt Network Auth, хуже подставляется в QML-тестах. Свой оркестратор на уже существующем транспорте проще заглушить.

### Транспорт: form POST в том же `CHttpTransport`

`post` получает необязательный content-type (по умолчанию JSON). Token exchange шлёт form-urlencoded. `channels.list` — обычный GET с Bearer access token. Счётчик `googleCount` отдельно от chat/kling.

Тест: `use_stub()`, в очередь — JSON токена, затем JSON `channels.list`. `CChannelAuth::complete_with_code(code)` обходит браузер и loopback. `openUrl` в тесте не вызывается (`use_stub` на auth). Живого Google в `shell_tests` нет.

### Схема `5 → 6`

```
CREATE TABLE channels (
  channel_id TEXT PRIMARY KEY,
  title TEXT NOT NULL
)
```

`PRAGMA user_version = 6`. Папки, ролики, бины, ассеты, задачи не трогать. Поиск по `title` канала не добавлять.

`CLibraryStore`: `channel_count`, `channel_id_at`, `channel_title`, `upsert_channel`, `remove_channel`. Модель для меню — список из store, не отдельная sqlite-вью.

### Токены в том же DPAPI-блобе

JSON дополняется `google_client_id`, `google_client_secret`, `channel_tokens` — объект `channel_id → refresh_token`. Access token не сохранять.

Рассматривалась отдельная запись Credential Manager на канал. Один блоб уже тестируется памятью `use_memory`; второй механизм — второй путь утечки в проверках.

Токен привязан к `channel_id`, библиотека хранит только метаданные. Отключение в этой библиотеке снимает и строку, и токен. Одна папка библиотеки на пользователя — нормальный сценарий ТЗ.

### UI: меню шапки и поля в настройках

`channelMenuButton` открывает `Menu` как у папки: фон `#282828`, пункт 16px / 44px, ховер tonal, радиус строки 8px. Пункт «Подключить канал», затем названия. У строки канала вложенный пункт «Отключить» или отдельная команда на строке. Hint кнопки больше не говорит «заглушка».

`channelConnected` — true, если в открытой библиотеке есть хотя бы один канал. Тест `test_brandAndChannels` меняется: клик открывает меню, без клиента и без библиотеки канал не появляется.

В диалоге «Модели» — поля client id (текст) и секрета (password, placeholder «Секрет Google задан»). Капсулы и радиус поля 4px как сейчас.

## Risks / Trade-offs

- [Google не отдаёт refresh_token без `prompt=consent`] → всегда `access_type=offline` и `prompt=consent select_account`; без refresh вход считается ошибкой, канал не пишется.
- [Brand account vs личный канал] → берём первый item `mine=true`; смена brand — повторный вход. Выбор канала из нескольких item в этом этапе не делается.
- [Пользователь не создал Desktop OAuth client] → вход не стартует, нужны настройки; в hint кнопки — коротко про client id.
- [Две библиотеки на одной машине] → токен общий по `channel_id`; отключение в одной снимает токен. Принимаем: ТЗ держит одну папку библиотеки.
- [Loopback режет корпоративный браузер / политика Google] → ошибка входа, список не меняется; custom scheme не добавляем.

## Migration Plan

При `open` версии 5: `CREATE TABLE channels`, `user_version = 6`. Откат схемы нет: старый exe базу v6 не открывает, как у 4 → 5. DPAPI без google-полей читается как пустой клиент и пустая карта токенов.

## Open Questions

Нет. Владелец OAuth-клиента, loopback, PKCE, scopes и заглушка тестов зафиксированы выше.
