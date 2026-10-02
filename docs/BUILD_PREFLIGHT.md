# Build preflight — Swift / macOS

Дата проверки: 2026-10-01. Это disposable preflight в отдельном scratch-каталоге, не реализация g-calendar и не изменение `Sources/`.

## Проверенное окружение

```text
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0
xcode-select -p: /Library/Developer/CommandLineTools
```

Scratch: `/Users/alexbeketov/.hermes/profiles/coder/cache/scratch/g-calendar-toolchain-parent`

## SwiftPM probe: tools-version 5.9

Пробован минимальный self-contained package без dependencies. Manifest (проверен и с отсутствующим `swiftLanguageVersions`, и с совместимым legacy API `swiftLanguageVersions: [.v5]`):

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GCalendarBuildPreflight",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "GCalendarBuildPreflight", targets: ["GCalendarBuildPreflight"])
    ],
    targets: [
        .executableTarget(name: "GCalendarBuildPreflight", path: "Sources/GCalendarBuildPreflight"),
        .testTarget(name: "GCalendarBuildPreflightTests", dependencies: ["GCalendarBuildPreflight"], path: "Tests/GCalendarBuildPreflightTests")
    ],
    swiftLanguageVersions: [.v5]
)
```

Команды, выполненные из scratch-каталога:

```sh
swift package dump-package
swift build
swift test
```

Все три завершились с exit code `1`. `dump-package` и `swift build` выдали `error: Invalid manifest` / `error: invalid manifests`; значимая часть linker output:

```text
Undefined symbols for architecture arm64:
  "PackageDescription.Package.__allocating_init(... swiftLanguageVersions: [PackageDescription.SwiftVersion]?, ...)", referenced from:
      _main in Package-1.o
ld: symbol(s) not found for architecture arm64
```

При явном `swiftLanguageVersions: [.v5]` дополнительно отсутствуют символы `PackageDescription.SwiftVersion.v5` и `type metadata accessor for PackageDescription.SwiftVersion`. Без явного language-version отсутствовал initializer symbol. `swift test` останавливался на той же ошибке манифеста до сборки/обнаружения XCTest: XCTest run не состоялся. Таким образом, переход с `swiftLanguageModes` на tools 5.9 и legacy `swiftLanguageVersions` проблему здесь не обходит. Фактический сбой — link манифеста против выбранной `PackageDescription` ManifestAPI; точную причину несоответствия компонентов CLT этим probe установить нельзя.

## Рабочий проверенный fallback: native `swiftc`

Из scratch-каталога успешно собран (`exit code 0`) arm64 Mach-O executable с `@main` SwiftUI `App`, импортирующий Foundation, AppKit, SwiftUI и UserNotifications:

```sh
mkdir -p build
swiftc -parse-as-library \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  AppEntry.swift Sources/GCalendarBuildPreflight/ProbeInvariant.swift \
  -o build/PreflightApp
file build/PreflightApp
```

Фактический результат:

```text
build/PreflightApp: Mach-O 64-bit executable arm64
```

Executable намеренно не запускался: проверялись compile/link, а не запуск GUI или permission flows.

Отдельно скомпилирован и запущен standalone executable с invariant checks (это НЕ XCTest и НЕ `swift test`):

```sh
swiftc -parse-as-library \
  Sources/GCalendarBuildPreflight/ProbeInvariant.swift StandaloneInvariantChecks.swift \
  -o build/StandaloneInvariantChecks
build/StandaloneInvariantChecks
```

Компиляция: exit code `0`. Запуск: exit code `0`, вывод:

```text
PASS trims spaces and newlines
PASS preserves non-whitespace
PASS maps whitespace-only input to empty
PASS: 3 standalone invariant checks
```

## Вывод и границы

Для быстрой локальной проверки исходников доступен прямой `swiftc`: он реально скомпилировал и слинковал минимальный SwiftUI executable и отдельно выполнил три synthetic invariant checks без Xcode, installs, сетевых зависимостей, system-config изменений и Google/credential обращений. SwiftPM/XCTest сейчас не подтверждены: `swift build` и `swift test` не проходят из-за линковки manifest API в активном CLT toolchain.

Probe не является готовым приложением: не собирался `.app` bundle, не проверялись `Info.plist`, assets/resources, signing, entitlements, sandbox, запуск UI, реальные g-calendar исходники или app-specific invariants. Standalone checks покрывают только временную whitespace-функцию. Для полного проекта прямой `swiftc` потребует явного перечисления файлов, ресурсов и параметров линковки; он не заменяет возможности SwiftPM.

Session ID: `20261001_173627_c42f86`.
