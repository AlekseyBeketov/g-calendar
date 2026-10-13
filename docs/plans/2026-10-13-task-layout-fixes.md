# Calendar order and task layout fixes

## Purpose / Big Picture

По прямому запросу Лехи переключатель календаря должен показывать День / Неделя / Месяц. В задачах первая доска должна целиком оставаться достижимой слева. Справа в шапке нужны две строки: сверху Создать, снизу шестерёнка настроек и справа селектор Колонки / Список. Меню на самих досках сохраняют многоточие. UI-проверка выполняется синтетическими offscreen окнами; управление пользовательским приложением не запрошено.

## Progress

- [x] 2026-10-13: дизайн задан сообщением пользователя; исходные правки сохранены в /private/tmp/g-calendar-task-layout/initial.patch.
- [x] Порядок календаря: точечная Swift-проверка allCases дала PASS; отдельный коммит отправляется в main.
- [x] Тест исходной версии выявил выход viewport под sidebar (FAIL); перенос padding на viewport исправляет это. 50 native assertions и сборка прошли; отдельный коммит отправляется в main.
- [ ] Перестроить шапку задач, проверить сборку и отправить отдельный коммит.
- [ ] Обновить dist/g-calendar.app и локальные индексы; сохранить результаты.

## Surprises & Discoveries

При ширине окна 1900 pt панель задач имеет x=245 и width=1655, но исходный NSScrollView занимает x=0, width=1900 и компенсирует sidebar offset -245. После переноса padding наружу NSScrollView имеет x=269, width=1607 и обычную левую границу 0. Изолированная страница не выявляла проблему; тест должен включать настоящий RootView с NavigationSplitView. Изменения RootView не потребовались. Исходные изменения пользователя не коммитятся.

## Decision Log

13 октября 2026: следовать конкретной двухстрочной раскладке пользователя без дополнительного согласования. Шестерёнка заменяет многоточие только в верхнем меню страницы задач. Использовать существующие темы и нативные меню; не добавлять анимации или внешние зависимости.

## Outcomes & Retrospective

Работа начата; итоговые проверки будут записаны после исправления.

## Context and Orientation

Sources/GCalendar/CalendarPresentation.swift задаёт порядок allCases переключателя. Sources/GCalendar/TaskWorkspaceView.swift содержит workspaceHeader, workspaceActions, taskBoards и TaskBoardMenu; Sources/GCalendar/CalendarLayout.swift задаёт ширины досок. scripts/test-native-ui.sh запускает синтетические нативные тесты, scripts/test.sh — инварианты, scripts/build-app.sh создаёт bundle.

## Plan of Work

Порядок CalendarPresentationMode изменён без смены значения по умолчанию. В taskBoards padding 24 перенесён с HStack документа на ScrollView только для колонок. Tests/TaskWorkspaceNativeTests.swift и scripts/test-task-workspace-ui.sh компилируют настоящие RootView и TaskWorkspaceView с синтетическими данными и test-only измерителями рамок. В workspaceActions заменить HStack на VStack с Создать сверху и HStack меню/селектора снизу. Добавить параметр символа и индикатора меню TaskBoardMenu для верхнего меню; остальные вызовы сохраняют старые значения.

## Concrete Steps

Рабочая директория /Users/alexbeketov/g-calendar. Проверки: rtk proxy ./scripts/test.sh, rtk proxy ./scripts/test-task-workspace-ui.sh и rtk proxy ./scripts/build-app.sh. Перед каждым коммитом rtk git diff --check и просмотр rtk git diff --cached. Stage только явные пути текущей задачи, затем rtk git commit и rtk git push origin main. После исходных коммитов rtk proxy ./scripts/index-code.sh. Не включать исходные пользовательские правки, dist или индексы.

## Validation and Acceptance

При левом крае прокрутки первая доска целиком помещается внутри viewport; последняя достигается прокруткой вправо. Проверить широкие окна и несколько размеров, переход список/колонки и изменение размера. В шапке Создать находится выше настроек и селектора; шестерёнка слева от селектора. Кнопки сохраняют полный hit region, pointing-hand cursor и доступные названия. Сборка должна завершиться с APP_BUNDLE=/Users/alexbeketov/g-calendar/dist/g-calendar.app; она не подтверждает ручную UI-проверку.

## Idempotence and Recovery

Копии исходных файлов и patch находятся в /private/tmp/g-calendar-task-layout. Не сбрасывать рабочие правки и не переписывать историю. Проверки используют синтетические данные, Google mutations не выполняются. При обновлении origin/main объединять историю обычным merge с сохранением рабочих правок.

## Artifacts and Notes

Скриншот пользователя показывает недостижимую левую часть первой доски. Временное воспроизведение /private/tmp/g-calendar-task-layout/scroll-probe печатает геометрию и возвращает exit 1 при недостижимой первой доске.

## Interfaces and Dependencies

Сохраняются SwiftUI/AppKit и WorkspaceViewModel. Новый контейнер, если требуется для общей проверки, принимает viewport CGSize и содержимое scroll document через ViewBuilder; он не меняет сортировку, фильтры или mutations.

План создан 13 октября 2026 по конкретным инструкциям пользователя; выполнение последовательное.
