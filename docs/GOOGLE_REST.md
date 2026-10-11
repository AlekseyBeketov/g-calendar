# Google REST: план внедрения и сравнения

Отдельная ветка `codex/google-rest` сохраняет оптимизированный `gws` как исходный транспорт и добавляет прямой Swift `URLSession`. Переключение применяется после перезапуска. Вход выполняет владелец через собственный Desktop OAuth client; агент не извлекает credentials `gws` и не инициирует Google авторизацию.

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
2. GET повторяется ограниченно при 429, quota 403 и временных 5xx с backoff. Mutation никогда автоматически не повторяется после неопределённого результата. Точный GET обязателен и для REST.
3. Desktop OAuth: системный браузер, PKCE S256, случайный state, callback только на loopback; refresh token и конфигурация — Keychain, access token — память, обновление токена single-flight. [Google native OAuth](https://developers.google.com/identity/protocols/oauth2/native-app).
4. Кэш, metadata, journal и notification identifiers REST отделены от legacy gws и привязаны к OAuth client/Google account subject. Переключение аккаунта/транспорта запрещено при незавершённой проверке записи. Demo/test режимы остаются синтетическими.
5. Настройки позволяют импортировать Desktop JSON, выполнить вход и выбрать транспорт. До авторизации REST показывает необходимость настройки. Никакие ключи, токены и пользовательские данные не добавляются в Git.

## Сравнение через OpenResearch

Используется [официальный OpenResearch](https://github.com/alphaXiv/OpenResearch), прочитанный исходник `603558cbf18207fdf758cc50b317a06e01ba2354`, установленный `orx 0.2.17`. Локальная работа не требует аккаунта или платного compute. Store и артефакты находятся в исключённой `.hermes/research/`; браузер, дополнительные агенты и GitHub sync выключены.

Одна фиксированная команда и committed конфигурации вариантов; каждый run связан с commit и неизменяемым архивом исходников. До авторизации выполняются только синтетические fixtures и сбои: retry, cancellation, pagination, token refresh, uncertain mutation. Их времена не доказывают преимущество REST в реальной сети.

После авторизации владельцем: минимум 20 парных read-only cold/warm серий при одинаковых диапазонах, полях и concurrency. Проверка равенства объектов выполняется в памяти; сохраняются только p50/p95, числа запросов/байтов/повторов/ошибок и среда. Реальные Google записи и искусственные сбои в аккаунте не используются.

## Статус

План согласован поручением владельца. REST реализация и стенд — в работе. Авторизация, живое A/B и ручная UI приёмка ещё не выполнены.
