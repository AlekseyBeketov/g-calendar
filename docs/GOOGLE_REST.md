# Google REST: план внедрения и сравнения

Прямой Swift `URLSession` доступен наряду с оптимизированным `gws`. Смена транспорта применяется автоматическим перезапуском приложения. Вход выполняет владелец через собственный Desktop OAuth client; агент не извлекает credentials `gws` и не инициирует Google авторизацию.

## Квоты и стоимость

Официальная документация проверена через Context7 и TinyFish 2026-10-11.

| API | Опубликованный лимит | Ограничения |
| --- | --- | --- |
| Tasks | 50 000 запросов в сутки | Courtesy quota; фактические значения проекта нужно проверить в Cloud Console. |
| Calendar | 1 000 000 запросов в сутки на проект | Порог начислений, не индивидуальная квота каждого пользователя. |
| Calendar | 10 000 в минуту на проект; 600 на пользователя/проект | Скользящее окно, возможны дополнительные операционные ограничения. |

Стандартное использование Calendar не требует дополнительной оплаты. Google сообщает о планируемых изменениях тарификации с уведомлением минимум за 90 дней. У Calendar PATCH расходует три единицы квоты. Источники: [Calendar quota/pricing](https://developers.google.com/workspace/calendar/api/guides/quota), [events.patch](https://developers.google.com/workspace/calendar/api/v3/reference/events/patch), [Tasks limits](https://developers.google.com/workspace/tasks/limits).

Наш текущий full: семь календарей, пять списков, 14 вызовов — Calendar 8, Tasks 6. Условные 100 full и 100 изменений задач в день (write + exact GET + scoped list) дают около 900 Tasks запросов. Для Calendar 100 full, 100 range reads, 100 prefetch и 100 PATCH + exact GET — около 2600 единиц. Дополнительные страницы, повторы и пользователи увеличивают расход. Для личного использования запас большой; фактические квоты проекта проверяются после создания OAuth client.

## Реализация

1. REST adapter строит разрешённые HTTP endpoints из существующей операции и JSON параметров. Общие readers, bounded concurrency 4, кэш, verified reducer и recovery journal сохраняются. Одна URLSession переиспользует соединения; GET отменяется при ненужной навигации.
2. GET повторяется ограниченно при 429, quota 403 и временных 5xx с backoff, который прерывается отменой. Mutation никогда автоматически не повторяется после неопределённого результата. Точный GET обязателен и для REST.
3. Desktop OAuth: системный браузер, PKCE S256, случайный state, callback только на loopback; refresh token и конфигурация — Keychain, access token — память, обновление токена single-flight. [Google native OAuth](https://developers.google.com/identity/protocols/oauth2/native-app).
4. Кэш, metadata, journal и notification identifiers REST отделены от legacy gws и привязаны к OAuth client/Google account subject. Переключение аккаунта/транспорта запрещено при незавершённой проверке записи. Повторный вход для восстановления разрешён только с тем же client и подтверждённым Google subject; журнал сохраняется. Отказ получения токена до запуска mutation HTTP доказанно не отправляет запись и не блокирует последующий вход. Demo/test режимы остаются синтетическими.
5. Настройки позволяют импортировать Desktop JSON, выполнить вход и выбрать транспорт. До авторизации REST показывает необходимость настройки. Никакие ключи, токены и пользовательские данные не добавляются в Git.

## Что понадобится владельцу

В своём Google Cloud project включить Google Calendar API и Google Tasks API, настроить OAuth consent screen и создать OAuth client типа **Desktop app**. В режиме Testing добавить свой Google аккаунт в Audience → Test users. Скачать JSON и импортировать через настройки приложения; не добавлять файл в репозиторий и не передавать refresh token в чат. После импорта приложение автоматически открывает вход в браузере. Разрешить указанные Calendar/Tasks scopes: успешный вход автоматически выбирает REST и перезапускает приложение. При сбое запуска новой копии старая остаётся открытой и показывает инструкцию восстановления.

Если consent screen имеет внешний тип и статус Testing, refresh token с Calendar/Tasks scopes истекает через семь дней; потребуется повторный вход. Это режим Google, а не ошибка кэша. [OAuth token expiration](https://developers.google.com/identity/protocols/oauth2).

## Сравнение через OpenResearch

Используется [официальный OpenResearch](https://github.com/alphaXiv/OpenResearch), прочитанный исходник `603558cbf18207fdf758cc50b317a06e01ba2354`, установленный `orx 0.2.17`. Локальная работа не требует аккаунта или платного compute. Store и артефакты находятся в исключённой `.hermes/research/`; браузер, дополнительные агенты и GitHub sync выключены.

Локальный проект зарегистрирован: `a94fd8ec-0f24-48cd-ba51-56d11be59dd5`, команда `./scripts/benchmark-transports.sh`. Store: `.hermes/research/openresearch`. Для локального daemon используются `--no-browser --no-agent --no-telemetry`, `ORX_NO_UPDATE_CHECK=1` и `OPENRESEARCH_CLI_DISABLE_UPDATE=1`. Dashboard — loopback `127.0.0.1:4793`, если daemon запущен.

Одна фиксированная команда и committed конфигурации вариантов; каждый run связан с commit и неизменяемым архивом исходников. До авторизации выполняются только синтетические fixtures и сбои: retry, cancellation, pagination, token refresh, uncertain mutation. Их времена не доказывают преимущество REST в реальной сети.

После авторизации владельцем: минимум 20 парных read-only cold/warm серий при одинаковых диапазонах, полях и concurrency. Проверка равенства объектов выполняется в памяти; сохраняются только p50/p95, числа запросов/байтов/повторов/ошибок и среда. Реальные Google записи и искусственные сбои в аккаунте не используются.

### Запуск после авторизации

Для сравнения подключи в REST тот же Google аккаунт, который использует `gws`. Импорт JSON и вход выполняются в приложении; перезапуск происходит автоматически. `gws` остаётся установленным для контрольных чтений.

```bash
./scripts/benchmark-transports.sh --live-read-only
```

Стенд использует `benchmarks/transport-config.json`: минимум 20 серий, фиксированные start/end/timeZone, `transport: paired`. Перед будущим исследованием при необходимости обнови даты и зафиксируй конфигурацию новым коммитом. Измеряются full cold/warm, один список, exact GET, диапазон с сохранённой metadata и возврат в кэш. Warm включает предварительное чтение вне измерения; cold создаёт новый REST session/token provider, но не сбрасывает внутренний OAuth cache `gws`.

При несовпадении объектов сравнение останавливается: сначала нужно исключить разные аккаунты или изменение данных во время чтения. `logical_operation_calls` считает команды приложения; REST отдельно сообщает фактические API/OAuth HTTP попытки. Внутренние сетевые повторы `gws` не наблюдаются. Payload bytes — размер полученного JSON, не сетевой трафик. Реальная задержка Save→UI, FPS и ручная UI приёмка требуют отдельных измерений после авторизации.

Для живого OpenResearch создай новый baseline с командой `./scripts/benchmark-transports.sh --live-read-only`; все его потомки наследуют эту команду и сохраняют парный режим. Синтетическое дерево оставь неизменяемым.

### Выполненные синтетические эксперименты

Baseline `74c07260-3c17-4b83-86c0-24b0ca7b852b`, run `ea6cd638-e423-4015-a60e-71ee125aa063`, source `076853a`: `done`, 30 отчётов, равенство fixtures подтверждено. Каждый performance сценарий имеет 20 samples. Размеры: 7 календарей, 5 списков, 146 задач и 31 событие; обычный full — 14 вызовов, paged full — 19, один список и exact GET — по одному, range с metadata — семь, возврат в кэш — ноль.

| Финальный вариант | Experiment | Run | Source | Статус |
| --- | --- | --- | --- | --- |
| gws fixture process | `84e9ed2e-e2e4-4f74-8321-7031926def1a` | `88624858-26dc-4f28-8b24-1a0f0901be6c` | `83f680e` | done |
| REST fake HTTP | `dea7e1f6-eb2e-453c-b530-73e0283a21eb` | `f26bb9c2-6fc1-4391-b1cd-71fd6f82b659` | `0378dca` | done |

| Сценарий | gws fixture p50 / p95, мс | REST fake HTTP p50 / p95, мс |
| --- | --- | --- |
| full | 384.512 / 399.829 | 2.356 / 3.226 |
| paged full | 563.261 / 599.894 | 2.059 / 2.271 |
| один список | 97.484 / 101.819 | 0.167 / 0.175 |
| exact GET | 90.759 / 100.979 | 0.022 / 0.024 |
| range с metadata | 196.055 / 206.552 | 1.767 / 1.838 |
| возврат в кэш | 0.008 / 0.012 | 0.002 / 0.002 |

Это измерение накладных расходов **fixture process против fake HTTP**. Оно не измеряет Google сеть, TLS и внутреннюю работу настоящего `gws`; победитель живого сравнения не выбран. Первый gws/REST child сообщал SHA внешнего checkout в JSON, хотя OpenResearch записал правильные source commits. Исправление воспроизведено в новых child nodes; отвеченные узлы сохранены. Raw numeric evidence: `benchmarks/results/transport-synthetic-2026-10-11.json`. Более позднее восстановление OAuth/backoff проверено отдельно invariant suite.

### Возобновление локального OpenResearch

```bash
export ORX_DATA_DIR="$PWD/.hermes/research/openresearch"
export ORX_NO_UPDATE_CHECK=1 OPENRESEARCH_CLI_DISABLE_UPDATE=1
/Users/alexbeketov/.cargo/bin/orx up --port 4793 --no-browser --no-agent --no-telemetry
```

В другом терминале с теми же переменными доступны `orx projects`, `orx runs a94fd8ec-0f24-48cd-ba51-56d11be59dd5` и `orx logs <run-id>`. Store и локальные experiment branches не публикуются; для воспроизведения на другой машине нужно зарегистрировать репозиторий заново и создать committed transport configs. Общие исходники стенда и численный отчёт находятся в REST ветке.

## Статус

Обновление 2026-10-11: владелец выполнил OAuth вход и подтвердил работу приложения после исправления маршрута Google Tasks (`@me` должен оставаться служебным литералом). Импорт запускает вход автоматически, успешный вход выбирает REST; смена транспорта и авторизации применяются автоматическим перезапуском. Живое A/B сравнение ещё впереди. Следующий абзац сохраняет результаты этапа до авторизации.

План согласован поручением владельца. REST транспорт и OAuth реализованы до авторизации владельцем. Проверки: 732 offline model assertions + 4 локальных loopback assertions (736 суммарно), 918 native assertions; сборка успешна, `dist/g-calendar.app`. Синтетический стенд и пять локальных OpenResearch запусков успешно завершены. Дополнительная проверка production коммита `9e74682` дала 30 успешных отчётов стенда. Для callback проверки: `G_CALENDAR_TEST_LOOPBACK=1 ./scripts/test.sh`; требуется разрешение на локальный socket, Google сеть не используется. Авторизация, живое A/B и ручная UI приёмка ещё не выполнены.
