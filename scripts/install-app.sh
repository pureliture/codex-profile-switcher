#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex Profile Switcher"
BUNDLE_ID="dev.pureliture.codex-profile-switcher"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
SOURCE_APP="$ROOT/.build/artifacts/$APP_NAME.app"
TARGET_APP="$INSTALL_DIR/$APP_NAME.app"

bash "$ROOT/scripts/build-app.sh"

mkdir -p "$INSTALL_DIR"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
open "$TARGET_APP"

echo "Installed $TARGET_APP"
