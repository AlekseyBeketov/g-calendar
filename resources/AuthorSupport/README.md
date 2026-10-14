# Ресурсы поддержки автора

CloudTips: https://pay.cloudtips.ru/p/bf792932 — основной способ. Boosty: https://boosty.to/gcalendar/donate — дополнительный. QR предоставлены владельцем 2026-10-14; PNG сохранены без изменения. Исходный Boosty QR кодирует https://boosty.to/gcalendar/donate?qr=true — ту же страницу с QR-маркером сервиса. Проверка `scripts/test-author-support.sh` декодирует каждый QR через Vision и сравнивает с отдельным точным qrURL; browser/clipboard используют адрес без маркера.

Все четыре PNG хранятся в этой папке репозитория. `scripts/build-app.sh` копирует её в `g-calendar.app/Contents/Resources/AuthorSupport` до подписи приложения. Во время работы `AuthorSupportAssets.bundled` читает изображения через `Bundle.main.resourceURL`: исходный checkout, временные вложения и файлы на компьютере автора для установленного приложения не нужны.

Логотипы получены 2026-10-14 из официальных страниц:

- CloudTips: https://cloudtips.ru/, SVG https://static.tildacdn.com/tild3465-3233-4263-b937-316135666261/Horiz.svg. Для AppKit SVG растрирован в прозрачный PNG шириной 640 px; содержимое марки сохранено.
- Boosty: https://boosty.to/, иконка https://boosty.to/apple-touch-icon-180x180.png. Исходный PNG сохранён.

Логотипы служат для идентификации внешних платёжных страниц; марки принадлежат соответствующим владельцам. Лицензия проекта не распространяется на эти марки, отдельная лицензия на их использование в исходных файлах не указана. В ресурсы не включены пользовательские скриншоты, платёжные credentials или сгенерированные изображения QR.
