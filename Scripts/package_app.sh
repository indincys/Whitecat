#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.indincys.Whitecat}"
APPCAST_URL="${APPCAST_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SCRATCH_PATH="${SCRATCH_PATH:-/tmp/whitecat-release-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
RELEASES_DIR="$OUTPUT_DIR/releases"
APP_NAME="Whitecat"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
EXECUTABLE_NAME="Whitecat"
SWIFT_CACHE_DIR="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/whitecat-swiftpm-module-cache}"
CLANG_CACHE_DIR="${CLANG_MODULE_CACHE_PATH:-/tmp/whitecat-clang-module-cache}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-}"
INFO_TEMPLATE="$ROOT_DIR/Configs/Info.plist.template"
SPARKLE_FRAMEWORK="$ROOT_DIR/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
USE_HARDENED_RUNTIME=1

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  USE_HARDENED_RUNTIME=0
fi

mkdir -p "$OUTPUT_DIR" "$RELEASES_DIR" "$SWIFT_CACHE_DIR" "$CLANG_CACHE_DIR"
rm -rf "$APP_DIR"

env \
  DEVELOPER_DIR="$DEVELOPER_DIR" \
  SWIFTPM_MODULECACHE_OVERRIDE="$SWIFT_CACHE_DIR" \
  CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" \
  swift build -c release --product WhitecatApp --disable-sandbox --scratch-path "$SCRATCH_PATH"

BIN_PATH="$(env \
  DEVELOPER_DIR="$DEVELOPER_DIR" \
  SWIFTPM_MODULECACHE_OVERRIDE="$SWIFT_CACHE_DIR" \
  CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" \
  swift build -c release --product WhitecatApp --disable-sandbox --scratch-path "$SCRATCH_PATH" --show-bin-path)"

mkdir -p \
  "$APP_DIR/Contents/MacOS" \
  "$APP_DIR/Contents/Frameworks" \
  "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/WhitecatApp" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"

# SwiftPM-linked binaries don't automatically search inside an app bundle's Frameworks directory.
# Add the standard app-bundle rpath before signing so Sparkle can be resolved at launch.
if ! otool -l "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
fi

INFO_PLIST="$APP_DIR/Contents/Info.plist"
sed \
  -e "s#__VERSION__#$VERSION#g" \
  -e "s#__BUILD__#$BUILD_NUMBER#g" \
  -e "s#__APPCAST_URL__#$APPCAST_URL#g" \
  -e "s#__SPARKLE_PUBLIC_ED_KEY__#$SPARKLE_PUBLIC_ED_KEY#g" \
  -e "s#__BUNDLE_IDENTIFIER__#$BUNDLE_IDENTIFIER#g" \
  "$INFO_TEMPLATE" > "$INFO_PLIST"

codesign_path() {
  local target="$1"
  local codesign_args=(--force --sign "$SIGNING_IDENTITY")

  # Ad-hoc builds are for local use only. Signing them with the hardened runtime
  # enables library validation, which blocks the embedded Sparkle framework from loading.
  if [[ "$USE_HARDENED_RUNTIME" -eq 1 ]]; then
    codesign_args+=(--options runtime --timestamp)
  fi

  if [[ -n "$ENTITLEMENTS_PATH" && "$target" == "$APP_DIR" ]]; then
    codesign_args+=(--entitlements "$ENTITLEMENTS_PATH")
  fi

  codesign "${codesign_args[@]}" "$target"
}

if [[ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" ]]; then
  for xpc in "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/"*.xpc; do
    [[ -e "$xpc" ]] && codesign_path "$xpc"
  done
fi

if [[ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" ]]; then
  codesign_path "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
fi

if [[ -f "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" ]]; then
  codesign_path "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
fi

codesign_path "$APP_DIR/Contents/Frameworks/Sparkle.framework"
codesign_path "$APP_DIR"

ZIP_PATH="$RELEASES_DIR/${APP_NAME}-${VERSION}.zip"
DMG_PATH="$RELEASES_DIR/${APP_NAME}-${VERSION}.dmg"
rm -f "$ZIP_PATH" "$DMG_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "App bundle: $APP_DIR"
echo "ZIP: $ZIP_PATH"
echo "DMG: $DMG_PATH"
