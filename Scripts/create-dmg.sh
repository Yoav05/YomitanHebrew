#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="Yomitan Hebrew.app"
APP_PATH="$DIST_DIR/$APP_NAME"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

"$SCRIPT_DIR/build-app.sh"

if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "Не найдено собранное приложение: $APP_PATH"
  exit 1
fi
if [[ ! -f "$INFO_PLIST" ]]; then
  print -u2 "Не найден Info.plist: $INFO_PLIST"
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST")
BINARY_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE"
if [[ ! -x "$BINARY_PATH" ]]; then
  print -u2 "Не найден исполняемый файл: $BINARY_PATH"
  exit 1
fi

BINARY_ARCHS=$(lipo -archs "$BINARY_PATH")
ARCH_LABEL=${BINARY_ARCHS// /-}
VERSION_LABEL=$(printf '%s' "$VERSION" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-')
DMG_NAME="Yomitan-Hebrew-$VERSION_LABEL-$ARCH_LABEL.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

YOMITAN_DMG_TEMP=""
YOMITAN_DMG_MOUNT=""
YOMITAN_DMG_MOUNTED=0

cleanup() {
  if (( YOMITAN_DMG_MOUNTED )); then
    hdiutil detach "$YOMITAN_DMG_MOUNT" -quiet >/dev/null 2>&1 \
      || hdiutil detach "$YOMITAN_DMG_MOUNT" -force -quiet >/dev/null 2>&1 \
      || true
  fi
  if [[ -n "$YOMITAN_DMG_TEMP" && -d "$YOMITAN_DMG_TEMP" ]]; then
    rm -rf -- "$YOMITAN_DMG_TEMP"
  fi
}
trap cleanup EXIT

YOMITAN_DMG_TEMP=$(mktemp -d "${TMPDIR%/}/yomitan-hebrew-dmg.XXXXXX")
YOMITAN_DMG_STAGE="$YOMITAN_DMG_TEMP/volume"
YOMITAN_DMG_MOUNT="$YOMITAN_DMG_TEMP/mount"
YOMITAN_DMG_IMAGE="$YOMITAN_DMG_TEMP/$DMG_NAME"
mkdir -p "$YOMITAN_DMG_STAGE" "$YOMITAN_DMG_MOUNT"

ditto "$APP_PATH" "$YOMITAN_DMG_STAGE/$APP_NAME"
ln -s /Applications "$YOMITAN_DMG_STAGE/Applications"

hdiutil create \
  -volname "Yomitan Hebrew $VERSION" \
  -srcfolder "$YOMITAN_DMG_STAGE" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -nospotlight \
  -ov \
  "$YOMITAN_DMG_IMAGE"

hdiutil verify "$YOMITAN_DMG_IMAGE"
hdiutil attach \
  -readonly \
  -nobrowse \
  -noautoopen \
  -mountpoint "$YOMITAN_DMG_MOUNT" \
  -quiet \
  "$YOMITAN_DMG_IMAGE"
YOMITAN_DMG_MOUNTED=1

if [[ ! -d "$YOMITAN_DMG_MOUNT/$APP_NAME" ]]; then
  print -u2 "В DMG отсутствует $APP_NAME"
  exit 1
fi
if [[ ! -L "$YOMITAN_DMG_MOUNT/Applications" ]] \
  || [[ $(readlink "$YOMITAN_DMG_MOUNT/Applications") != "/Applications" ]]; then
  print -u2 "В DMG отсутствует корректный ярлык Applications"
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$YOMITAN_DMG_MOUNT/$APP_NAME"

hdiutil detach "$YOMITAN_DMG_MOUNT" -quiet
YOMITAN_DMG_MOUNTED=0

mv -f "$YOMITAN_DMG_IMAGE" "$DMG_PATH"
print "Создан: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
