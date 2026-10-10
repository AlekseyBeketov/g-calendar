# Pointer cursor для кликабельных affordances

**Статус:** superseded 2026-10-10. Этот исторический план заменён явной пользовательской политикой: pointing-hand обязателен на всей области доступного действия, включая native кнопки и кликабельные отступы. Актуальные правила — AGENTS.md и docs/ui.md; реализация — этап 6 [плана доработок](2026-10-10-workspace-improvements.md). Старые ограничения ниже не являются действующими инструкциями. UI проверяет Леха вручную; computer use и UI automation не применяются.

## Цель

В подходящих местах показывать pointer/pointing-hand cursor при наведении на пользовательские action targets, чтобы визуально отличать их от обычного содержимого. Сохранить native macOS/SwiftUI behavior, accessibility semantics и корректное восстановление курсора после hover.

## Объём

- Провести inventory реальных интерактивных affordances: custom clickable rows/cards, ссылки и элементы, чей hover сейчас не даёт понятного указания на действие.
- Использовать platform-appropriate механизм только там, где native control не предоставляет подходящий cursor сам.
- Сохранить системное поведение для стандартных кнопок и других native controls; не добавлять cursor modifiers повсеместно без подтверждения необходимости.
- Не обозначать pointer-курсор как интерактивные текстовые/selectable области, draggable surfaces, disabled controls и декоративные/non-actionable regions.
- Не менять hit areas, keyboard activation, drag behavior, layout или accessibility labels ради визуального cursor treatment.

## Приёмка

- На macOS наведением проверены обычное состояние и выход с каждого изменённого action target; cursor корректно возвращается к системному видом при переходе между actionable/non-actionable областями.
- Pointer показывается только на активных действиях; text selection, drag-and-drop, disabled/read-only и декоративные зоны сохраняют ожидаемый native cursor.
- Mouse click, keyboard/VoiceOver accessibility semantics, focus и hit testing не регрессируют; использовать synthetic demo/fixtures, не личные данные и не live Google writes.
- Выполнить относящиеся к изменениям UI tests и сборку; визуальный cursor behavior подтвердить на актуальном bundle, не делать вывод о работе pointer только по compile.

## Общие правила

Короткое правило для команды: pointer cursor уместен для настоящих доступных действий там, где это поддерживает native поведение; не назначать его тексту для выделения, draggable или недействующим областям. Общая политика должна быть отражена в корневых project rules до реализации этой задачи.
