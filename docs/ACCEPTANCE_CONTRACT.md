# Приёмочный контракт исходного задания

Это приёмочные требования, не отчёт о выполненных проверках. Обновлено 2026-10-05 с учётом прямых разрешений владельца; текущие доказательства находятся в docs/verification.md и docs/STATUS.md.

## A. Реальный результат
- Есть исходники и воспроизводимый build из репозитория.
- Есть proper `.app` bundle для macOS, не web-wrapper.
- Приложение действительно запускается. Сборка без запуска недостаточна.
- Стиль Material-inspired согласуется с macOS interaction/accessibility.
- У каждого критерия в отчёте статус: passed / failed / not-run / needs-human-verification. Последние два не равны passed.

## B. Google-доступ и приватность
- Используется текущая рабочая авторизация `gws` без token export/копирования credential blobs.
- Process invocation выполняется argument vector без shell interpolation. PATH графического приложения не полагается на shell profile.
- Calendar/task-list pagination не отбрасывается. Missing/error JSON не превращается в успешный пустой результат.
- Успех real read-only smoke подтверждается командами и privacy-safe counts/metadata, а не личными названиями задач и событий.
- Тестовый fake transport явно маркирован как fixture; он не является доказательством реальной интеграции.
- Calendar reader access запрещает UI mutations; owner/writer учитываются.
- Production/личные Google объекты агентам изменять запрещено. Узкое исключение: пользователь разрешил создать для этого run минимум synthetic Calendar event и Task с уникальным marker, через actual app adapter/UI, с GET/read-back и private exact-ID ledger; без attendees/invites/email. Владелец отдельно разрешил edit/complete/reopen/delete собственных тестовых задач, списков и событий; разрешение зафиксировано в docs/HUMAN_APPROVALS.md. Очистка относится только к созданным в выбранном запуске exact IDs. Standalone fixture и `gws` smoke не являются UI acceptance.

## C. Даты и синхронизация
- Google Tasks due — date-only; existing Google Tasks time не объявляется доступным через API.
- Local reminders маркированы local-only. Не создаются скрытые Calendar events-копии.
- all-day events имеют exclusive end-date; вывод учитывает timezone и границы дат.
- Network/auth errors не уничтожают существующий cached snapshot.
- Sync status отражает stale/offline/error; UI не показывает ложное «синхронизировано».
- Если offline write queue не реализована, offline mutations явно недоступны, а не теряются и не притворяются сохранёнными.
- Не заявляются unsupported recurring/starred/reminder features как full Google parity.

## D. Нативные уведомления
- Proper bundle identifier и UserNotifications, не browser alerts.
- Permission prompt только по явному действию пользователя.
- Есть schedule/cancel/reschedule/dedup логика и соответствующие focused tests.
- Закрытие окна и Quit различаются; lifecycle документирован.
- Focus, notification settings, sleep и явный quit описаны как OS/lifecycle ограничения.
- Реальная видимая доставка баннера — needs-human-verification, пока не получено permission и не проведён human-observed test.
- Notification click открывает соответствующую цель, если функция заявлена реализованной.
- Calendar event reminders в MVP ограничены opt-in локальным exact-time напоминанием на этом Mac для одного timed non-recurring event; это не mirror Google preferences и не Apple Calendar parity. All-day/recurring остаются вне scope.
- Calendar week/day includes dated tasks in each date's timeless row and undated tasks once in a separate `Без срока` region; the latter are not duplicated across seven days.

## E. Выпуск и расходы
- Нет обязательного платного backend, подписки, telemetry по умолчанию или новых paid keys.
- Стоимость/ограничения подписания, notarization и App Store не смешиваются с бесплатной локальной сборкой.
- Credentials, IDs личных аккаунтов и personal cache не попадают в tracked files или публичные screenshots.
- `.DS_Store` и существующий `.codegraph/` пользователя не удаляются.
- No commit/push/public release без явного подтверждения.

## F. Порядок проверки

- Спецификация и план предшествуют реализации.
- Fixture tests, native lifecycle и внешний UI QA имеют отдельные доказательства.
- Сводка агента не заменяет build/test/read-back и human-observed banner.
- Владелец делает коммиты. Полная внешняя приёмка не объявляется завершённой при недоступном Computer Use.
