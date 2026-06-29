#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Codex Profile Switcher"
PRODUCT="CodexProfileSwitcherApp"
BUNDLE_ID="dev.pureliture.codex-profile-switcher"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ARTIFACTS_DIR="$ROOT_DIR/.build/run-artifacts"
APP_BUNDLE="$RUN_ARTIFACTS_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_RESOURCES="$APP_CONTENTS/Resources"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_NAME="AppIcon"
ICON_FILE="$ROOT_DIR/assets/$ICON_NAME.icns"

cd "$ROOT_DIR"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --product "$PRODUCT"
BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cp "$ICON_FILE" "$APP_RESOURCES/$ICON_NAME.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --options runtime --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
