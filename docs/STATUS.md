# Статус g-calendar

Обновлено: 2026-10-05. Реализация продолжается; полная внешняя приёмка открыта.

Утверждён Pixel Paper + компактные task rows Color Atlas. Отвергнутые варианты удалены. В коде реализованы восстановление неподтверждённых записей, sidebar targets, адаптивные headers, metadata строк задач и content-fit формы с общими отступами 24/16/8 pt.

Последний оптимизированный current-source fixture suite: exit 0, 268 assertions. Один предшествующий прогон завершился timeout в synthetic GUI-path launcher fixture; повтор без изменения исходников прошёл. Оптимизированная native app ранее собрана с notification-test. Последние правки explicit ledger, selection, overdue/metadata accessibility и сообщения напоминаний ещё требуют актуальной сборки; разрешение на неё запрошено после отказа automatic approval review.

Два собственных Google lifecycle завершены с 11 проверенными шагами и удалением всех трёх созданных объектов в каждом запуске. Проверено безопасное продолжение cleanup через exact read-only recheck. Последний свежий запуск остановился до первой записи по timeout; оставленных объектов нет.

Один тест уведомления от actual bundle доставлен в Центр уведомлений; видимый баннер подтверждается владельцем отдельно. После разрешения владельца закрыта старая обычная копия и восстановлена работа Computer Use с изолированным demo. Подтверждены клики по тексту, иконке, пустой части и краю task-list row; create/edit-cancel/complete/reopen и симметричные 24 pt отступы task/reminder forms. Эти наблюдения относятся к предыдущей сборке. Снимок календаря выявил обрезанную метку 08:00; открытие Settings вызывает SIGTRAP в SkyComputerUseService, само приложение остаётся живым. Полная UI-приёмка и GUI baseline открыты.

Работа фиксируется в [ExecPlan](plans/2026-10-05-final-product-completion.md), [OpenSpec](../openspec/changes/g-calendar-mvp/tasks.md), [дизайне](../design/DESIGN.md) и [проверках](verification.md). Live scope — [HUMAN_APPROVALS.md](HUMAN_APPROVALS.md). Цель активна. Владелец разрешил коммит и пуш текущего checkpoint, затем продолжение цели и отдельный этап установщика. Основная удалённая ветка — main; master отсутствует, точное назначение пуша уточняется. Этот checkpoint не заявляет завершение приёмки или готовность публичного релиза.

Checkpoint review выявило межпроцессную гонку MutationJournal. Задача 7.2 вновь открыта; live writes не возобновляются до исправления. Следующий этап после сохранения checkpoint — фиксация этого дефекта и обрезания 08:00.
