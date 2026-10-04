#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_NAME="Yomitan Hebrew.app"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_PATH="$OUTPUT_DIR/$APP_NAME"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$PROJECT_DIR"
swift build -c release --product YomitanHebrew --disable-sandbox
BIN_DIR=$(swift build -c release --show-bin-path --disable-sandbox)

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/YomitanHebrew" "$APP_PATH/Contents/MacOS/YomitanHebrew"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

codesign --force --sign - "$APP_PATH"
echo "$APP_PATH"
