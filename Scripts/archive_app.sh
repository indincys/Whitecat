#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:?VERSION is required}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
RELEASES_DIR="$OUTPUT_DIR/releases"
APP_NAME="Whitecat"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$RELEASES_DIR/${APP_NAME}-${VERSION}.zip"
DMG_PATH="$RELEASES_DIR/${APP_NAME}-${VERSION}.dmg"

mkdir -p "$RELEASES_DIR"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found at $APP_DIR" >&2
  exit 1
fi

rm -f "$ZIP_PATH" "$DMG_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "ZIP: $ZIP_PATH"
echo "DMG: $DMG_PATH"
