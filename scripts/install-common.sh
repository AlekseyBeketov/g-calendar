#!/bin/bash
# Shared macOS installer primitives. Sourcing this file does not modify anything.
GC_BUNDLE_ID='com.alexbeketov.gcalendar'
GC_INSTALL_STAGE=''
GC_INSTALL_RESTORE=0
GC_INSTALL_APP=''
GC_INSTALL_BACKUP=''

gc_fail() { printf 'g-calendar: %s\n' "$*" >&2; return 1; }
gc_plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }
gc_check_platform() {
  local system="$1" architecture="$2" major="${3%%.*}"
  [[ "$system" == Darwin ]] || { gc_fail 'Нужна macOS 13+ на Apple Silicon.'; return 1; }
  [[ "$architecture" == arm64 ]] || { gc_fail 'Сборка поддерживает только Apple Silicon (arm64).'; return 1; }
  [[ "$major" =~ ^[0-9]+$ && "$major" -ge 13 ]] || { gc_fail 'Нужна macOS 13 или новее.'; return 1; }
}
gc_host_supported() { gc_check_platform "$(/usr/bin/uname -s)" "$(/usr/bin/uname -m)" "$(/usr/bin/sw_vers -productVersion)"; }
gc_macho_words() { /usr/bin/od -An -tu4 -j "$2" -N "$3" "$1"; }
gc_verify_macho() {
  local binary="$1" header magic cpu subtype filetype commands commandbytes flags reserved
  local length offset=32 count command size extra platform version declarations=0
  header="$(gc_macho_words "$binary" 0 32)" || return 1
  header="$(printf '%s\n' "$header" | /usr/bin/tr '\n' ' ')"
  read -r magic cpu subtype filetype commands commandbytes flags reserved <<< "$header"
  [[ "$magic" == 4277009103 && "$cpu" == 16777228 && "$subtype" == 0 && "$filetype" == 2 ]] || { gc_fail 'Ожидался thin arm64 Mach-O executable.'; return 1; }
  [[ "$commands" =~ ^[0-9]+$ && "$commandbytes" =~ ^[0-9]+$ && "$commands" -gt 0 && "$commands" -le 4096 && "$commandbytes" -le 1048576 ]] || { gc_fail 'Некорректные Mach-O load commands.'; return 1; }
  length="$(/usr/bin/stat -f %z "$binary")" || return 1
  [[ "$length" =~ ^[0-9]+$ && "$length" -ge $((32 + commandbytes)) ]] || { gc_fail 'Обрезанный Mach-O executable.'; return 1; }
  for ((count=0; count<commands; count++)); do
    [[ $((offset + 8)) -le $((32 + commandbytes)) ]] || return 1
    header="$(gc_macho_words "$binary" "$offset" 8)" || return 1
    read -r command size <<< "$header"
    [[ "$command" =~ ^[0-9]+$ && "$size" =~ ^[0-9]+$ && "$size" -ge 8 && $((size % 8)) == 0 && $((offset + size)) -le $((32 + commandbytes)) ]] || { gc_fail 'Некорректный Mach-O command size.'; return 1; }
    case "$command" in
      50) # LC_BUILD_VERSION: platform, minos (Apple mach-o/loader.h).
        [[ "$size" -ge 24 ]] || return 1
        extra="$(gc_macho_words "$binary" $((offset + 8)) 8)" || return 1
        read -r platform version <<< "$extra"
        [[ "$platform" == 1 && "$version" == 851968 ]] || { gc_fail 'Mach-O должен иметь MACOS deployment target 13.0.'; return 1; }
        declarations=$((declarations + 1));;
      36) # LC_VERSION_MIN_MACOSX: accepted legacy macOS declaration.
        [[ "$size" -ge 16 ]] || return 1
        extra="$(gc_macho_words "$binary" $((offset + 8)) 4)" || return 1
        read -r version <<< "$extra"
        [[ "$version" == 851968 ]] || { gc_fail 'Legacy Mach-O deployment target отличается от 13.0.'; return 1; }
        declarations=$((declarations + 1));;
      37|47|48) gc_fail 'Другой Mach-O platform target.'; return 1;;
    esac
    offset=$((offset + size))
  done
  [[ "$offset" == $((32 + commandbytes)) && "$declarations" == 1 ]] || { gc_fail 'Нужна ровно одна Mach-O macOS platform declaration.'; return 1; }
}
gc_verify_bundle() {
  local app="$1" executable minimum actual
  [[ -d "$app" && ! -L "$app" && -f "$app/Contents/Info.plist" && ! -L "$app/Contents/Info.plist" ]] || { gc_fail 'Некорректный bundle приложения.'; return 1; }
  [[ "$(gc_plist "$app" CFBundleIdentifier)" == "$GC_BUNDLE_ID" ]] || { gc_fail 'Другой bundle ID: приложение не будет изменено.'; return 1; }
  [[ "$(gc_plist "$app" CFBundlePackageType)" == APPL ]] || { gc_fail 'Bundle должен иметь тип APPL.'; return 1; }
  executable="$(gc_plist "$app" CFBundleExecutable)"
  [[ "$executable" == g-calendar && -x "$app/Contents/MacOS/$executable" && ! -L "$app/Contents/MacOS/$executable" ]] || { gc_fail 'Отсутствует ожидаемый executable.'; return 1; }
  gc_verify_macho "$app/Contents/MacOS/$executable" || return 1
  minimum="$(gc_plist "$app" LSMinimumSystemVersion)"
  [[ "$minimum" == 13.0 ]] || { gc_fail 'Неожиданная минимальная версия macOS.'; return 1; }
  /usr/bin/codesign --verify --strict -R "=identifier \"$GC_BUNDLE_ID\"" "$app" || return 1
  actual="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)"
  printf '%s\n' "$actual" | /usr/bin/grep -qx "Identifier=$GC_BUNDLE_ID" || { gc_fail 'Подпись не соответствует bundle ID.'; return 1; }
}
gc_verify_release_signature() {
  local app="$1" team="$2" details assessment
  [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || { gc_fail 'Укажите ожидаемый Developer ID Team ID (10 символов).'; return 1; }
  gc_verify_bundle "$app" || return 1
  /usr/bin/codesign --verify --strict -R "=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$team\"" "$app" || return 1
  details="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)"
  [[ "$details" == *"TeamIdentifier=$team"* && "$details" == *"runtime"* && "$details" == *"Timestamp="* ]] || { gc_fail 'Ожидалась hardened-runtime Developer ID подпись издателя с secure timestamp.'; return 1; }
  assessment="$(/usr/sbin/spctl --assess --type execute --verbose=2 "$app" 2>&1)" || { printf '%s\n' "$assessment" >&2; return 1; }
  printf '%s\n' "$assessment" | /usr/bin/grep -qx 'source=Notarized Developer ID' || { gc_fail 'Gatekeeper не подтвердил notarized Developer ID.'; return 1; }
  # User installation relies on Gatekeeper's notarized Developer ID assessment.
  # A separate release pipeline validates the stapled ticket with developer tools.
}
gc_lock_fd_modern() { /usr/bin/lockf -s -t 0 9 2>/dev/null; }
gc_lock_fd_legacy() {
  # macOS 13's lockf only supports command mode. System Perl's core flock uses
  # the same inherited open-file description; FD 9 in this shell retains lease.
  [[ -x /usr/bin/perl ]] || { gc_fail 'Системный lockf не поддерживает FD mode и Perl fallback недоступен.'; return 1; }
  /usr/bin/perl -MFcntl=:flock -e 'flock(STDIN, LOCK_EX | LOCK_NB) or exit 75;' <&9
}
gc_lock_fd() {
  local status
  if gc_lock_fd_modern; then return 0; else status=$?; fi
  if [[ "$status" == 64 ]]; then gc_lock_fd_legacy; else return "$status"; fi
}
gc_assert_not_running() {
  local command processes
  processes="$(/bin/ps -ww -axo comm=)" || { gc_fail 'Не удалось проверить запущенные приложения.'; return 1; }
  while IFS= read -r command; do
    case "$command" in *'/Contents/MacOS/g-calendar')
      gc_fail 'Закройте g-calendar и повторите установку. Приложение не закрывается автоматически.'; return 1;;
    esac
  done <<< "$processes"
}
gc_prepare_destination() {
  local destination="$1" lock
  [[ "$destination" == /* && "$destination" != / && "$destination" != *$'\n'* ]] || { gc_fail 'Destination должен быть абсолютным каталогом.'; return 1; }
  [[ ! -L "$destination" ]] || { gc_fail 'Destination не должен быть symlink.'; return 1; }
  mkdir -p "$destination" || return 1
  GC_INSTALL_DEST="$(cd "$destination" && pwd -P)"
  [[ -w "$GC_INSTALL_DEST" ]] || { gc_fail 'Нет права записи в destination.'; return 1; }
  GC_INSTALL_APP="$GC_INSTALL_DEST/g-calendar.app"
  GC_INSTALL_BACKUP="$GC_INSTALL_DEST/.g-calendar-previous.app"
  lock="$GC_INSTALL_DEST/.g-calendar-install.lock"
  [[ ! -L "$lock" && ( ! -e "$lock" || -f "$lock" ) ]] || { gc_fail 'Небезопасный installer lock.'; return 1; }
  if [[ -e "$lock" && "$(/usr/bin/stat -f %u "$lock")" != "$(/usr/bin/id -u)" ]]; then gc_fail 'Installer lock принадлежит другому пользователю.'; return 1; fi
  (umask 077; : >> "$lock") || return 1
  chmod 600 "$lock" || return 1
  exec 9>> "$lock"
  gc_lock_fd || { gc_fail 'Другой установщик уже работает или lock недоступен. Повторите позже.'; return 1; }
  # Keep the same inode permanently. lockf's inherited descriptor holds the lease.
  trap gc_install_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
}
gc_install_cleanup() {
  local status=$?
  if [[ "$GC_INSTALL_RESTORE" == 1 && -d "$GC_INSTALL_BACKUP" && ! -e "$GC_INSTALL_APP" ]]; then
    mv "$GC_INSTALL_BACKUP" "$GC_INSTALL_APP" || printf '%s\n' 'Не удалось восстановить bundle; повторите --rollback.' >&2
  fi
  if [[ -n "$GC_INSTALL_STAGE" && -d "$GC_INSTALL_STAGE" ]]; then rm -rf "$GC_INSTALL_STAGE"; fi
  return "$status"
}
gc_ditto() {
  /usr/bin/env -u DITTONORSRC -u DITTOABORT -u DITTO_TEST_OPTIONS -u DITTOKEEPBINARIESPATTERN -u DITTOKEEPBINARIESDIR /usr/bin/ditto --rsrc --extattr --qtn --acl "$@"
}
gc_copy_bundle() { gc_ditto "$1" "$2"; }
gc_install_bundle() {
  local candidate="$1" team="${2:-}"
  gc_verify_bundle "$candidate" || return 1
  if [[ -n "$team" ]]; then gc_verify_release_signature "$candidate" "$team" || return 1; fi
  gc_assert_not_running || return 1
  if [[ -e "$GC_INSTALL_APP" || -L "$GC_INSTALL_APP" ]]; then gc_verify_bundle "$GC_INSTALL_APP" || return 1; fi
  if [[ -e "$GC_INSTALL_BACKUP" || -L "$GC_INSTALL_BACKUP" ]]; then gc_verify_bundle "$GC_INSTALL_BACKUP" || return 1; fi
  [[ -e "$GC_INSTALL_APP" || ! -e "$GC_INSTALL_BACKUP" ]] || { gc_fail 'Предыдущая замена прервана. Сначала выполните --rollback.'; return 1; }
  GC_INSTALL_STAGE="$(mktemp -d "$GC_INSTALL_DEST/.g-calendar-stage.XXXXXX")" || return 1
  gc_copy_bundle "$candidate" "$GC_INSTALL_STAGE/g-calendar.app" || return 1
  gc_verify_bundle "$GC_INSTALL_STAGE/g-calendar.app" || return 1
  if [[ -n "$team" ]]; then gc_verify_release_signature "$GC_INSTALL_STAGE/g-calendar.app" "$team" || return 1; fi
  gc_assert_not_running || return 1
  if [[ -e "$GC_INSTALL_APP" ]]; then
    if [[ -e "$GC_INSTALL_BACKUP" ]]; then rm -rf "$GC_INSTALL_BACKUP"; fi
    mv "$GC_INSTALL_APP" "$GC_INSTALL_BACKUP" || return 1
    GC_INSTALL_RESTORE=1
  fi
  mv "$GC_INSTALL_STAGE/g-calendar.app" "$GC_INSTALL_APP" || return 1
  GC_INSTALL_RESTORE=0
  printf 'INSTALLED_APP=%s\n' "$GC_INSTALL_APP"
  printf '%s\n' 'Данные, настройки и Google credentials сохранены. Запуск: open установленного .app.'
}
gc_rollback_bundle() {
  gc_assert_not_running || return 1
  [[ -d "$GC_INSTALL_BACKUP" ]] || { gc_fail 'Нет сохранённой предыдущей версии.'; return 1; }
  gc_verify_bundle "$GC_INSTALL_BACKUP" || return 1
  if [[ -e "$GC_INSTALL_APP" || -L "$GC_INSTALL_APP" ]]; then gc_verify_bundle "$GC_INSTALL_APP" || return 1; fi
  GC_INSTALL_STAGE="$(mktemp -d "$GC_INSTALL_DEST/.g-calendar-stage.XXXXXX")" || return 1
  if [[ -e "$GC_INSTALL_APP" ]]; then mv "$GC_INSTALL_APP" "$GC_INSTALL_STAGE/g-calendar.app" || return 1; fi
  GC_INSTALL_RESTORE=1
  mv "$GC_INSTALL_BACKUP" "$GC_INSTALL_APP" || return 1
  GC_INSTALL_RESTORE=0
  if [[ -e "$GC_INSTALL_STAGE/g-calendar.app" ]]; then mv "$GC_INSTALL_STAGE/g-calendar.app" "$GC_INSTALL_BACKUP" || return 1; fi
  printf 'ROLLED_BACK_APP=%s\n' "$GC_INSTALL_APP"
}
gc_uninstall_bundle() {
  gc_assert_not_running || return 1
  if [[ ! -e "$GC_INSTALL_APP" && ! -L "$GC_INSTALL_APP" ]]; then printf '%s\n' 'Приложение уже отсутствует; данные сохранены.'; return 0; fi
  gc_verify_bundle "$GC_INSTALL_APP" || return 1
  rm -rf "$GC_INSTALL_APP" || return 1
  printf '%s\n' 'Приложение удалено. Данные и сохранённая rollback-версия не удалены.'
}
gc_zipinfo() { /usr/bin/env ZIPINFO= ZIPINFOOPT= /usr/bin/zipinfo "$@"; }
gc_unzip() { /usr/bin/env UNZIP= UNZIPOPT= /usr/bin/unzip -P '' "$@"; }
gc_validate_archive() {
  local archive="$1" listing
  # Bound expansion before CRC testing, which itself decompresses every entry.
  # The current app has no symlinks or special files; reject before extraction.
  gc_zipinfo -l "$archive" | /usr/bin/awk '
    /^[bclps?]/ {exit 1}
    /^[-d]/ {bytes+=$4; count++; if(bytes>536870912 || count>10000)exit 1}
    END {if(count==0 || bytes>536870912 || count>10000)exit 1}' || { gc_fail 'ZIP содержит links/special files или слишком велик.'; return 1; }
  listing="$(gc_zipinfo -1 "$archive")" || return 1
  [[ -n "$listing" ]] || { gc_fail 'Пустой ZIP.'; return 1; }
  printf '%s\n' "$listing" | LC_ALL=C /usr/bin/awk '
    /[^ -~]/ || /\\/ || /:/ || /^\// {exit 1}
    $0=="._g-calendar.app" {count++; next}
    {n=split($0,a,"/"); if(a[1]!="g-calendar.app")exit 1; for(i=1;i<=n;i++)if(a[i]==".." || a[i]==".")exit 1; count++}
    END {if(count>10000)exit 1}' || { gc_fail 'ZIP содержит небезопасные пути.'; return 1; }
  gc_unzip -tq "$archive" >/dev/null || { gc_fail 'Повреждённый или зашифрованный ZIP.'; return 1; }
}
gc_extract_archive() {
  [[ -d "$2" && ! -L "$2" && "$(/usr/bin/stat -f %u "$2")" == "$(/usr/bin/id -u)" && "$(/usr/bin/stat -f %Lp "$2")" == 700 ]] || { gc_fail 'Для распаковки нужен приватный каталог текущего пользователя.'; return 1; }
  [[ -z "$(/usr/bin/find "$2" -mindepth 1 -maxdepth 1 -print -quit)" ]] || { gc_fail 'Каталог распаковки должен быть пустым.'; return 1; }
  gc_validate_archive "$1" || return 1
  # ditto consumes AppleDouble metadata instead of leaving extra ._* resources
  # inside the signed bundle, and preserves resource forks/tickets/quarantine.
  gc_ditto -x -k "$1" "$2" || return 1
  [[ -z "$(/usr/bin/find "$2" -type l -print -quit)" ]] || { gc_fail 'Links в распакованном ZIP запрещены.'; return 1; }
  [[ "$(/usr/bin/find "$2" -mindepth 1 -maxdepth 1 -print)" == "$2/g-calendar.app" ]] || { gc_fail 'Неожиданный root распакованного ZIP.'; return 1; }
  gc_verify_bundle "$2/g-calendar.app" || return 1
}
gc_verify_digest() {
  local actual expected="$2"
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { gc_fail 'Некорректный SHA256.'; return 1; }
  actual="$(/usr/bin/shasum -a 256 "$1")" || return 1
  actual="${actual%% *}"
  [[ "$actual" == "$(printf '%s' "$expected" | /usr/bin/tr 'A-F' 'a-f')" ]] || { gc_fail 'SHA256 не совпал; приложение не заменено.'; return 1; }
}
