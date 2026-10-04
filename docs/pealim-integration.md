# Интеграция с Pealim

Yomitan Hebrew обращается к поиску Pealim напрямую через `URLSession`. WebView, браузерное расширение и локальная копия словаря для этого не используются.

```text
выделенное слово
→ SelectedTextReader
→ LookupViewModel
→ PealimClient
→ JSON или HTML Pealim
→ PealimSearchResult
→ интерфейс и Anki
```

## От выделенного слова до запроса

Глобальный хоткей вызывает `AppDelegate.lookUpSelection()`. `SelectedTextReader` сначала пытается прочитать `kAXSelectedTextAttribute` через macOS Accessibility API. Если приложение не предоставляет выделение таким способом, используется резервный вариант: Yomitan Hebrew временно выполняет `⌘C`, читает pasteboard, а затем восстанавливает его прежнее содержимое.

Полученная строка передаётся в `LookupViewModel.lookup()`. Модель удаляет пробелы по краям, ограничивает запрос 160 символами и вызывает `PealimClient.search()` асинхронно. Идентификатор поколения запроса не позволяет медленному старому ответу заменить результаты более нового поиска.

Ключевые файлы:

- [`AppDelegate.swift`](../Sources/YomitanHebrew/App/AppDelegate.swift) — запуск поиска после хоткея;
- [`SelectedTextReader.swift`](../Sources/YomitanHebrew/Services/SelectedTextReader.swift) — чтение выделенного текста;
- [`LookupViewModel.swift`](../Sources/YomitanHebrew/App/LookupViewModel.swift) — состояние поиска и подготовка результата для интерфейса.

## HTTP-запрос

`PealimClient` формирует URL через `URLComponents`, поэтому выбранное слово корректно кодируется как query-параметр:

```http
GET https://www.pealim.com/ru/search/?q=לְחַפֵּשׂ
Accept: application/json
Accept-Language: ru
```

Это обычный поисковый endpoint русской версии сайта. Адрес `/ru/dict/` используется не для поиска, а для ссылок на отдельные словарные статьи, полученные в результатах.

Сетевой код находится в [`PealimClient.swift`](../Sources/YomitanCore/Pealim/PealimClient.swift).

## JSON-first

Сначала клиент запрашивает JSON. `PealimJSONParser` объединяет группы `he-words` и `ru-words`, после чего преобразует каждую запись в общую модель `PealimSearchResult`.

Используемые поля ответа:

- `lemma.he` и `lemma.tr` — слово с огласовками и транскрипция;
- `meaning` — русский перевод;
- `root` — корень;
- `part-of-speech` — часть речи;
- `binyan` или `mishkal` — грамматическая информация;
- `link` — относительная ссылка на статью `/ru/dict/...`.

Служебные коды частей речи и биньянов переводятся в понятные русские подписи. Неизвестные коды не удаляются, а остаются видимыми пользователю.

Разбор реализован в [`PealimJSONParser.swift`](../Sources/YomitanCore/Pealim/PealimJSONParser.swift).

## HTML fallback

Контракт Pealim не является документированным стабильным API, поэтому предусмотрен резервный путь:

1. Если Pealim проигнорировал `Accept: application/json` и сразу вернул HTML, клиент распознаёт и разбирает этот же ответ.
2. Если JSON недоступен, не декодируется либо сервер отвечает `406`/`415`, выполняется второй GET с `Accept: text/html,application/xhtml+xml`.
3. `PealimHTMLParser` читает только карточки результатов `.verb-search-result` и извлекает слово, транскрипцию, корень, грамматику, перевод, ссылку и доступный URL аудио.
4. Повреждённая карточка пропускается, не скрывая остальные корректные результаты.

HTML-разбор находится в [`PealimHTMLParser.swift`](../Sources/YomitanCore/Pealim/PealimHTMLParser.swift).

## Результат и отображение

Оба парсера возвращают одну модель [`PealimSearchResult`](../Sources/YomitanCore/Models/PealimSearchResult.swift), содержащую:

- `lemma`;
- `transcription`;
- `root`;
- `partOfSpeech`;
- `meaning`;
- `sourceURL`;
- `audioURL`.

`LookupViewModel` публикует результаты для SwiftUI, автоматически выбирает первый вариант и переносит его поля в редактируемый черновик. Пользователь может изменить перевод, транскрипцию или грамматику перед отправкой карточки в Anki. Кнопка «Открыть Pealim» открывает исходный `sourceURL` в браузере.

## Надёжность и ограничения

- Приложение делает точечный запрос только для выбранного слова и не скачивает словарь целиком.
- Оно не требует аккаунта Pealim или API-ключа и не добавляет собственную авторизацию.
- Форматы JSON и HTML могут измениться со стороны Pealim. JSON-first, HTML fallback и fixture-тесты снижают риск, но не устраняют его полностью.
- JSON- и HTML-парсеры тестируются на сохранённых примерах ответов в [`Tests/YomitanCoreTests/Fixtures`](../Tests/YomitanCoreTests/Fixtures).

