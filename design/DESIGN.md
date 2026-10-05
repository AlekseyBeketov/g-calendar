---
version: alpha
name: g-calendar Pixel Paper
colors:
  primary: "#0B57D0"
  primary-container: "#D3E3FD"
  canvas: "#F7F9FC"
  surface: "#FFFFFF"
  on-surface: "#202124"
  secondary-text: "#505866"
  success: "#188038"
  warning: "#B06000"
  error: "#C5221F"
---

# Утверждённая айдентика g-calendar

Выбор владельца от 2026-10-05: Pixel Paper (вариант 1) — основа всего приложения. Из Color Atlas (вариант 4) переносится только организация списка задач: компактные строки, выровненный срок с понятным состоянием, тег списка и полезные метаданные. Совместная pane задач и календаря, сиреневая тема и Glass-направление не входят в выбранную компоновку.

## Рабочая область

Классический sidebar 220–260 pt, Calendar/Tasks, отдельные контексты календарей и списков. Календарь открывается в Week, поддерживает Day и горизонтальный scroll при недостаточной ширине. Непрозрачная рабочая поверхность, тонкие линии сетки, pastel events, одна общая ось времени. Пустой date-only ряд компактный; задачи без срока — один сворачиваемый регион.

Task workspace: заголовок текущего списка, поиск в общем toolbar, одна группа фильтров, переключатель List/Columns и создание задачи. Основной List состоит из сворачиваемых непустых групп с counts. Строка: completion target, title, local metadata icons, выровненный due/status, тег списка и независимое menu. Длинные названия увеличивают высоту; в узком окне metadata переносится целиком ниже title, основные действия остаются доступны. Просрочка обозначается icon/text и error color; сегодняшняя дата не становится красной автоматически. Даты человекочитаемые; arbitrary tags, приоритеты и Google-synced reminder time не выдумываются. Теги отражают существующий список, значки — реальные local reminder/favorite.

## Типографика, размеры и состояния

SF system: title 22–24 pt semibold, section 14 pt semibold, body 13–14 pt, metadata 11–12 pt. Spacing 4/8/12/16/24/32 pt. Sidebar target 36–40 pt и full-row click area; task target минимум 44 pt, controls glyph и target имеют отдельные размеры. Радиусы 8–12 pt для controls, 16–18 pt для крупных поверхностей, pill для selection/filter. Нет тяжёлых рамок вокруг каждой задачи.

Light — основной сценарий пользователя; System остаётся default и Dark поддерживается через парные semantic roles. Primary blue — главное действие и selected state; белый текст на primary. Surface/ink не зависят от цвета Google calendar. Hover/pressed/disabled/focus имеют различимый feedback. Keyboard focus сохраняется нативным или явным контуром. Цвет не заменяет label/AX semantics.

## Формы и отступы

Task/event/list editors: content-sized VStack, единый внешний inset 24 pt, 16 pt между основными секциями, 8 pt внутри поля; заголовок наверху, footer внизу. Никаких растягивающихся Form с пустым центром и произвольной minHeight. Labels видны; date-only и local reminders явно различаются. При длинной ошибке/маленьком окне содержимое прокручивается, footer остаётся доступен. Создание показывает выбираемый writable calendar/task list; редактирование сохраняет исходную identity. Save/Cancel имеют Enter/Escape. После неопределённой записи показывается read-only recheck вместо повторного INSERT.

Отступы принимаются по коду и actual demo-window screenshots: task/event/list create/edit, settings, reminder popovers и confirmation dialogs, в Light/Dark и узком окне. Случайные даты, counts и цвета из generated PNG не являются логикой приложения.

## Референсы

[Pixel Paper](reference-overview.png) задаёт общую внешность; [выбранный список Color Atlas](task-list-reference.png) задаёт metadata alignment. Изображения — концепты с синтетическими данными, не screenshot текущего приложения. Самостоятельный calendar mark допускается доработка в существующем icon generator; Google G не используется. Стек SwiftUI/AppKit сохраняется.
