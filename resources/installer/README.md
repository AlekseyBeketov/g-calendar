# DMG resources

`finder-layout.bin` — намеренно созданный переносимый Finder layout: светлая поверхность Pixel Paper, приложение слева, Applications справа и инструкция снизу. При упаковке он копируется как `.DS_Store` только в ignored временный staging. Он не содержит имени пользователя, путей тома, alias bookmark или истории Finder.

Системная упаковка не требует Python и не управляет Finder через AppleScript. Для изменения расположения можно один раз пересоздать ресурс: Python + `ds_store==1.3.1`, затем `python3 resources/installer/make-layout.py`. Инструмент ds_store: https://github.com/dmgbuild/ds_store (MIT); код пакета не включён в репозиторий.

HTML-инструкция и отдельный CSS используют светлую Pixel Paper палитру и доступны без сети.
