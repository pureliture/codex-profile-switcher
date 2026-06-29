#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex Profile Switcher"
PRODUCT="CodexProfileSwitcherApp"
CONFIG="${CONFIG:-release}"
ARTIFACTS="$ROOT/.build/artifacts"
APP="$ARTIFACTS/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_NAME="AppIcon"
ICON_SOURCE="$ROOT/assets/app-icon.svg"

cd "$ROOT"
swift build -c "$CONFIG" --product "$PRODUCT"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/$CONFIG/$PRODUCT" "$MACOS/$APP_NAME"
cp "$ROOT/LICENSE" "$RESOURCES/LICENSE"
cp "$ROOT/NOTICE.md" "$RESOURCES/NOTICE.md"

make_icon() {
  local iconset="$RESOURCES/$ICON_NAME.iconset"
  rm -rf "$iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$ICON_SOURCE" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    local double=$((size * 2))
    sips -s format png -z "$double" "$double" "$ICON_SOURCE" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$RESOURCES/$ICON_NAME.icns"
  rm -rf "$iconset"
}

make_icon

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Codex Profile Switcher</string>
  <key>CFBundleIdentifier</key>
  <string>dev.pureliture.codex-profile-switcher</string>
  <key>CFBundleName</key>
  <string>Codex Profile Switcher</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Profile Switcher</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --options runtime --sign - "$APP" >/dev/null
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP" >/dev/null
fi

echo "Built $APP"
