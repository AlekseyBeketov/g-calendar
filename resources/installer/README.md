# DMG resources

Утверждённое оформление: светлый голубой фон с волнами, приложение слева, Applications справа, стрелка между ними и инструкция снизу. Настоящие значки и подписи рисует Finder; они не запечены в фоне.

`background.tiff` — непрозрачный фон 1280 × 840, логический размер 640 × 420 точек (144 DPI). Редактируемый источник — `render-background.swift`; собрать его через тот же `scripts/swift-toolchain.sh`, запустить с путём выходного TIFF. Картинка включается в `.installer/` самого DMG.

Перед первой упаковкой: `./scripts/setup-installer-tools.sh`. Скрипт создаёт ignored `.build/installer-layout-venv` и устанавливает только `ds-store==1.3.1` и `mac-alias==2.2.2` по закреплённым SHA-256 из `requirements.txt`. Они нужны только компьютеру, выпускающему DMG, и не входят в приложение. Обычная сборка/установка приложения не требует этих Python-пакетов.

`make-layout.py` создаёт `.DS_Store` непосредственно на временно смонтированном writable образе, чтобы alias фона содержал правильные volume/file IDs. Публичный fallback ограничен `/Volumes/g-calendar <version>`; путь checkout/имя автора не сохраняется. После сжатия проверяется разрешение того же alias на readonly mount. `verify-background-alias.swift` использует системное преобразование Carbon AliasRecord в bookmark именно для чтения формата Finder; API помечен deprecated Apple, но не используется в приложении.

Упаковщик не запускает Finder и не использует AppleScript. Размеры окна, позиции, ресурсы и внутренний alias проверяются отдельно; это не запись реального Finder UI. HTML-инструкция и CSS доступны без сети.

Первичные источники: [ds_store](https://github.com/dmgbuild/ds_store), [mac_alias](https://github.com/dmgbuild/mac_alias), [dmgbuild](https://github.com/dmgbuild/dmgbuild). Лицензии библиотек — MIT; их код в репозиторий не копируется.
