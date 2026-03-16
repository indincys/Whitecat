#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVES_DIR="${1:-$ROOT_DIR/dist/releases}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"
RELEASE_NOTES_URL_PREFIX="${RELEASE_NOTES_URL_PREFIX:-}"
FULL_RELEASE_NOTES_URL="${FULL_RELEASE_NOTES_URL:-}"
PRIVATE_ED_KEY="${PRIVATE_ED_KEY:-}"
PRIVATE_ED_KEY_PATH="${PRIVATE_ED_KEY_PATH:-}"
KEYCHAIN_SERVICE="Whitecat Sparkle EdDSA"
KEYCHAIN_ACCOUNT="sparkle-eddsa-private-key"

# Try Keychain if no key provided via env
if [[ -z "$PRIVATE_ED_KEY" && -z "$PRIVATE_ED_KEY_PATH" ]]; then
  if security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
    PRIVATE_ED_KEY="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w)"
  fi
fi
APPCAST_TOOL="${APPCAST_TOOL:-$ROOT_DIR/Vendor/SparkleTools/generate_appcast}"
STAGING_DIR="$(mktemp -d /tmp/whitecat-appcast.XXXXXX)"

cleanup() {
  rm -rf "$STAGING_DIR"
}

trap cleanup EXIT

if [[ ! -d "$ARCHIVES_DIR" ]]; then
  echo "Archives directory not found: $ARCHIVES_DIR" >&2
  exit 1
fi

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  echo "DOWNLOAD_URL_PREFIX is required." >&2
  exit 1
fi

[[ "$DOWNLOAD_URL_PREFIX" != */ ]] && DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX}/"
if [[ -n "$RELEASE_NOTES_URL_PREFIX" && "$RELEASE_NOTES_URL_PREFIX" != */ ]]; then
  RELEASE_NOTES_URL_PREFIX="${RELEASE_NOTES_URL_PREFIX}/"
fi

ARGS=(
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  --embed-release-notes
)

if [[ -n "$RELEASE_NOTES_URL_PREFIX" ]]; then
  ARGS+=(--release-notes-url-prefix "$RELEASE_NOTES_URL_PREFIX")
fi

if [[ -n "$FULL_RELEASE_NOTES_URL" ]]; then
  ARGS+=(--full-release-notes-url "$FULL_RELEASE_NOTES_URL")
fi

for archive in "$ARCHIVES_DIR"/*.zip; do
  [[ -e "$archive" ]] || continue
  cp "$archive" "$STAGING_DIR/"

  base_name="${archive:t:r}"
  for ext in html txt; do
    note_file="$ARCHIVES_DIR/$base_name.$ext"
    [[ -e "$note_file" ]] && cp "$note_file" "$STAGING_DIR/"
  done
done

[[ -e "$ARCHIVES_DIR/appcast.xml" ]] && cp "$ARCHIVES_DIR/appcast.xml" "$STAGING_DIR/"
[[ -d "$ARCHIVES_DIR/old_updates" ]] && cp -R "$ARCHIVES_DIR/old_updates" "$STAGING_DIR/"

if [[ -n "$PRIVATE_ED_KEY_PATH" ]]; then
  ARGS+=(--ed-key-file "$PRIVATE_ED_KEY_PATH")
  "$APPCAST_TOOL" "${ARGS[@]}" "$STAGING_DIR"
elif [[ -n "$PRIVATE_ED_KEY" ]]; then
  print -r -- "$PRIVATE_ED_KEY" | "$APPCAST_TOOL" --ed-key-file - "${ARGS[@]}" "$STAGING_DIR"
else
  "$APPCAST_TOOL" "${ARGS[@]}" "$STAGING_DIR"
fi

cp "$STAGING_DIR/appcast.xml" "$ARCHIVES_DIR/appcast.xml"
if [[ -d "$STAGING_DIR/old_updates" ]]; then
  rm -rf "$ARCHIVES_DIR/old_updates"
  cp -R "$STAGING_DIR/old_updates" "$ARCHIVES_DIR/"
fi
