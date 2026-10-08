# Работа с репозиторием

Это native SwiftUI/AppKit macOS-приложение. Рабочий target — arm64/macOS 13+; сборка и tests требуют Apple Command Line Tools. Package-manager workflow, `Package.swift` и Xcode project сейчас отсутствуют. Лицензия и условия публичного распространения ещё не выбраны: этот документ не предоставляет лицензию и не обещает приём contributions или сроки ответа.

## Перед изменениями

- Прочитайте [AGENTS.md](AGENTS.md), [README](README.md) и [открытые решения](docs/PENDING_DECISIONS.md).
- Для продуктовых изменений сверяйтесь с [repo-local OpenSpec](openspec/changes/g-calendar-mvp/). Исторически завершённые tasks не являются разрешением на новый live acceptance или публикацию.
- Сохраняйте нативные interaction/accessibility и существующий стиль соседних файлов. Делайте точечные изменения без попутного refactoring.
- Не изменяйте credentials, пользовательские данные, настройки macOS или publishing configuration в рамках обычной разработки.

## Проверки

Из корня checkout:

```sh
./scripts/build-app.sh
./scripts/test.sh
env G_CALENDAR_TEST_OPTIMIZE=1 ./scripts/test.sh
./scripts/test-native-ui.sh
./scripts/test-installers.sh
git diff --check
```

Model/native UI tests используют synthetic fixtures. Installer suite работает с собственными временными bundles/destinations, не с пользовательским `~/Applications`. `gws`, Google-аккаунт, OAuth и live writes для этих проверок не нужны. Native UI suite не заменяет визуальную приёмку, голосовой VoiceOver проход или проверку баннера уведомления.

Для documentation-only изменений достаточно проверить ссылки/пути/команды, shell syntax при описании скриптов, ignore rules и `git diff --check`; не выдавайте прежние результаты сборки или tests за новый прогон. Результаты продуктовой приёмки — [verification](docs/verification.md).

## Безопасные fixtures и диагностика

- Используйте только синтетические данные в tests, screenshots и bug reports. Для просмотра UI без Google завершите обычный экземпляр, затем после сборки выполните `open dist/g-calendar.app --args --demo`.
- Не прикладывайте OAuth tokens, raw Google responses, cache, reminder metadata, mutation journal/drafts и личные IDs. Локальные данные описаны в [INSTALLATION](docs/INSTALLATION.md#локальные-данные).
- Новая live Google-проверка требует отдельного разрешения и narrow synthetic scope с exact-ID ledger, read-back и удалением только собственных объектов. Историческое разрешение из docs не переносится на другие аккаунты/запуски.
- Не отключайте Gatekeeper и не удаляйте quarantine для обхода проверки.
- Private security reporting channel и support/SLA пока не определены. Не публикуйте чувствительные детали уязвимости в публичном отчёте; этот документ не объявляет security policy.

## Git hygiene и выпуск

`.gitignore` исключает локальные build/cache/user artifacts, а не весь JSON, editor configuration или fixtures. Ignore rules не защищают уже tracked файлы и не заменяют проверку diff на credentials и личные данные. Не используйте `git add -f` для кэшей, `dist/`, `.hermes/`, `.codegraph/` или пользовательских экспортов.

Перед коммитом выбирайте явные paths, просматривайте staged diff и выполняйте релевантные проверки. Следуйте [AGENTS.md](AGENTS.md) для правил коммита и push; никогда не переписывайте историю и не включайте unrelated work. Push исходников не является выпуском приложения.

Local ad-hoc bundle не является публичным подписанным релизом. Developer ID credentials, notarization, clean-Mac acceptance, лицензия и публикация — отдельные gates в [RELEASING](docs/RELEASING.md) и [PENDING_DECISIONS](docs/PENDING_DECISIONS.md).
