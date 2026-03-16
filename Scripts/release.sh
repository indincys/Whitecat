#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Whitecat"
DEFAULT_NOTES_FILE="$ROOT_DIR/release-notes.txt"
DOCS_DIR="$ROOT_DIR/docs"
DOCS_APPCAST_PATH="$DOCS_DIR/appcast.xml"
DOCS_OLD_UPDATES_PATH="$DOCS_DIR/old_updates"
BUILD_DIR="$ROOT_DIR/build"
OUTPUT_DIR="$ROOT_DIR/dist"
RELEASES_DIR="$OUTPUT_DIR/releases"
TEMP_NOTES_FILE=""
APPCAST_STAGE_DIR=""

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./Scripts/release.sh <version>

Example:
  CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  TEAM_BUNDLE_PREFIX="TEAMID" \
  ./Scripts/release.sh 0.1.8

Environment:
  BUILD_NUMBER         Optional. Defaults to the git commit count on HEAD.
  CODESIGN_IDENTITY    Optional. Defaults to "-" for ad-hoc signing.
  DRY_RUN              Optional. Set to 1 to stop before git push and GitHub release upload.
  GITHUB_TOKEN         Optional. Used for GitHub API calls if set.
  PRIVATE_ED_KEY       Optional. Sparkle private key content.
  PRIVATE_ED_KEY_PATH  Optional. Path to the Sparkle private key file. Defaults to ~/.config/whitecat/sparkle_private_key if present.
  SPARKLE_KEY_KEYCHAIN Optional. Set to 1 to read the private key from macOS login Keychain (default: try Keychain first).
  RELEASE_NOTES_FILE   Optional. Text file with one change per line.
  TEAM_BUNDLE_PREFIX   Required for signed releases unless ENTITLEMENTS_PATH is set.
  ENTITLEMENTS_PATH    Optional. Overrides the generated entitlements path.

This script:
  1. Builds and signs the app locally.
  2. Generates a Sparkle-signed appcast from the new ZIP asset.
  3. Commits docs/appcast.xml updates.
  4. Creates or reuses the release tag.
  5. Pushes the tag, publishes the GitHub Release, then pushes main.
EOF
}

cleanup() {
  [[ -n "$TEMP_NOTES_FILE" && -f "$TEMP_NOTES_FILE" ]] && rm -f "$TEMP_NOTES_FILE"
  [[ -n "$APPCAST_STAGE_DIR" && -d "$APPCAST_STAGE_DIR" ]] && rm -rf "$APPCAST_STAGE_DIR"
}

trap cleanup EXIT

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

VERSION="${1#v}"
TAG_NAME="v$VERSION"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-}"
DRY_RUN="${DRY_RUN:-0}"
DEFAULT_PRIVATE_KEY_PATH="${HOME}/.config/whitecat/sparkle_private_key"
GH_USER=""
GH_PASS=""

KEYCHAIN_SERVICE="Whitecat Sparkle EdDSA"
KEYCHAIN_ACCOUNT="sparkle-eddsa-private-key"
SPARKLE_KEY_KEYCHAIN="${SPARKLE_KEY_KEYCHAIN:-0}"

# Key resolution order: env var > env path > Keychain > default file
if [[ -z "${PRIVATE_ED_KEY:-}" && -z "${PRIVATE_ED_KEY_PATH:-}" ]]; then
  if security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
    PRIVATE_ED_KEY="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w)"
    SPARKLE_KEY_KEYCHAIN=1
    echo "Using Sparkle private key from macOS login Keychain."
  elif [[ -f "$DEFAULT_PRIVATE_KEY_PATH" ]]; then
    PRIVATE_ED_KEY_PATH="$DEFAULT_PRIVATE_KEY_PATH"
  fi
fi

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  fail "Version must use semantic versioning, for example 0.1.8."
fi

if [[ ! "$BUILD_NUMBER" =~ '^[0-9]+$' ]]; then
  fail "BUILD_NUMBER must be numeric."
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
  fail "Run releases from the local main branch."
fi

if [[ -n "$(git status --short)" ]]; then
  fail "Working tree must be clean before releasing."
fi

git fetch origin main --tags >/dev/null

ahead_behind="$(git rev-list --left-right --count origin/main...main)"
behind_count="${ahead_behind%%[[:space:]]*}"
if (( behind_count > 0 )); then
  fail "Local main is behind origin/main. Pull the latest changes before releasing."
fi

if [[ -z "${PRIVATE_ED_KEY:-}" && -z "${PRIVATE_ED_KEY_PATH:-}" ]]; then
  fail "Set PRIVATE_ED_KEY or PRIVATE_ED_KEY_PATH so Sparkle can sign the update archive."
fi

if [[ "$CODESIGN_IDENTITY" != "-" && -z "$ENTITLEMENTS_PATH" ]]; then
  [[ -n "${TEAM_BUNDLE_PREFIX:-}" ]] || fail "TEAM_BUNDLE_PREFIX is required for signed releases."
  mkdir -p "$BUILD_DIR"
  ENTITLEMENTS_PATH="$BUILD_DIR/Whitecat.entitlements"
  TEAM_BUNDLE_PREFIX="$TEAM_BUNDLE_PREFIX" "$ROOT_DIR/Scripts/render_entitlements.sh" "$ENTITLEMENTS_PATH" >/dev/null
fi

normalize_notes() {
  local source_file="$1"
  sed '/^[[:space:]]*$/d' "$source_file" | sed 's/^[[:space:]]*[-*][[:space:]]*//'
}

generate_notes_from_git() {
  local previous_tag
  previous_tag="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"

  TEMP_NOTES_FILE="$(mktemp /tmp/whitecat-release-notes.XXXXXX)"
  if [[ -n "$previous_tag" ]]; then
    git log --format='%s' "${previous_tag}..HEAD" > "$TEMP_NOTES_FILE"
  else
    git log --format='%s' HEAD > "$TEMP_NOTES_FILE"
  fi

  if [[ ! -s "$TEMP_NOTES_FILE" ]]; then
    printf 'Maintenance update\n' > "$TEMP_NOTES_FILE"
  fi

  printf '%s\n' "$TEMP_NOTES_FILE"
}

resolve_notes_file() {
  if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
    [[ -f "$RELEASE_NOTES_FILE" ]] || fail "Release notes file not found: $RELEASE_NOTES_FILE"
    printf '%s\n' "$RELEASE_NOTES_FILE"
    return
  fi

  if [[ -f "$DEFAULT_NOTES_FILE" ]]; then
    printf '%s\n' "$DEFAULT_NOTES_FILE"
    return
  fi

  generate_notes_from_git
}

resolve_repo_path() {
  local remote_url repo_path
  remote_url="$(git remote get-url origin)"
  repo_path="$(printf '%s\n' "$remote_url" | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')"
  [[ "$repo_path" == */* ]] || fail "Unable to parse GitHub repo from origin: $remote_url"
  printf '%s\n' "$repo_path"
}

REPO_PATH="$(resolve_repo_path)"
REPO_OWNER="${REPO_PATH%%/*}"
REPO_NAME="${REPO_PATH##*/}"
APPCAST_URL="${APPCAST_URL:-https://${REPO_OWNER}.github.io/${REPO_NAME}/appcast.xml}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/${REPO_PATH}/releases/download/${TAG_NAME}}"
FULL_RELEASE_NOTES_URL="${FULL_RELEASE_NOTES_URL:-https://github.com/${REPO_PATH}/releases/tag/${TAG_NAME}}"
ZIP_PATH="$RELEASES_DIR/${APP_NAME}-${VERSION}.zip"
DMG_PATH="$RELEASES_DIR/${APP_NAME}-${VERSION}.dmg"
NOTES_SOURCE_FILE="$(resolve_notes_file)"
NORMALIZED_NOTES_PATH="$BUILD_DIR/release-notes.normalized.txt"
RELEASE_BODY_PATH="$BUILD_DIR/release-body.md"
RELEASE_METADATA_PATH="$BUILD_DIR/release-metadata.txt"
APPCAST_ITEM_PATH="$BUILD_DIR/appcast-item.xml"

mkdir -p "$BUILD_DIR" "$RELEASES_DIR"
normalize_notes "$NOTES_SOURCE_FILE" > "$NORMALIZED_NOTES_PATH"

awk 'NF { print "- " $0 }' "$NORMALIZED_NOTES_PATH" > "$RELEASE_BODY_PATH"
if [[ ! -s "$RELEASE_BODY_PATH" ]]; then
  printf -- "- Maintenance update\n" > "$RELEASE_BODY_PATH"
fi

cp "$NORMALIZED_NOTES_PATH" "$RELEASES_DIR/${APP_NAME}-${VERSION}.txt"

VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
SIGNING_IDENTITY="$CODESIGN_IDENTITY" \
ENTITLEMENTS_PATH="$ENTITLEMENTS_PATH" \
APPCAST_URL="$APPCAST_URL" \
OUTPUT_DIR="$OUTPUT_DIR" \
"$ROOT_DIR/Scripts/package_app.sh"

[[ -f "$ZIP_PATH" ]] || fail "ZIP archive not found at $ZIP_PATH"
[[ -f "$DMG_PATH" ]] || fail "DMG archive not found at $DMG_PATH"

APPCAST_STAGE_DIR="$(mktemp -d /tmp/whitecat-release-appcast.XXXXXX)"
cp "$ZIP_PATH" "$APPCAST_STAGE_DIR/"
cp "$RELEASES_DIR/${APP_NAME}-${VERSION}.txt" "$APPCAST_STAGE_DIR/"
[[ -f "$DOCS_APPCAST_PATH" ]] && cp "$DOCS_APPCAST_PATH" "$APPCAST_STAGE_DIR/appcast.xml"
[[ -d "$DOCS_OLD_UPDATES_PATH" ]] && cp -R "$DOCS_OLD_UPDATES_PATH" "$APPCAST_STAGE_DIR/old_updates"

env \
  DOWNLOAD_URL_PREFIX="$DOWNLOAD_URL_PREFIX" \
  FULL_RELEASE_NOTES_URL="$FULL_RELEASE_NOTES_URL" \
  PRIVATE_ED_KEY="${PRIVATE_ED_KEY:-}" \
  PRIVATE_ED_KEY_PATH="${PRIVATE_ED_KEY_PATH:-}" \
  "$ROOT_DIR/Scripts/generate_appcast.sh" "$APPCAST_STAGE_DIR"

cp "$APPCAST_STAGE_DIR/appcast.xml" "$RELEASES_DIR/appcast.xml"
cp "$APPCAST_STAGE_DIR/appcast.xml" "$DOCS_APPCAST_PATH"

rm -rf "$RELEASES_DIR/old_updates" "$DOCS_OLD_UPDATES_PATH"
if [[ -d "$APPCAST_STAGE_DIR/old_updates" ]]; then
  cp -R "$APPCAST_STAGE_DIR/old_updates" "$RELEASES_DIR/old_updates"
  cp -R "$APPCAST_STAGE_DIR/old_updates" "$DOCS_OLD_UPDATES_PATH"
fi

grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$DOCS_APPCAST_PATH" \
  || fail "Generated appcast does not mention version $VERSION."
grep -q "releases/download/${TAG_NAME}/${APP_NAME}-${VERSION}.zip" "$DOCS_APPCAST_PATH" \
  || fail "Generated appcast does not contain the expected ZIP download URL."
grep -q "sparkle:edSignature=" "$DOCS_APPCAST_PATH" \
  || fail "Generated appcast is missing the Sparkle signature."

awk '
  /<item>/ { capture=1 }
  capture { print }
  /<\/item>/ && capture { exit }
' "$DOCS_APPCAST_PATH" > "$APPCAST_ITEM_PATH"

ZIP_SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
DMG_SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
cat > "$RELEASE_METADATA_PATH" <<EOF
VERSION=$VERSION
BUILD_NUMBER=$BUILD_NUMBER
TAG_NAME=$TAG_NAME
REPO_PATH=$REPO_PATH
APPCAST_URL=$APPCAST_URL
DOWNLOAD_URL_PREFIX=$DOWNLOAD_URL_PREFIX
ZIP_PATH=$ZIP_PATH
ZIP_SHA256=$ZIP_SHA
DMG_PATH=$DMG_PATH
DMG_SHA256=$DMG_SHA
EOF

commit_feed_if_needed() {
  if git diff --quiet -- "$DOCS_APPCAST_PATH" "$DOCS_OLD_UPDATES_PATH"; then
    return
  fi

  local add_paths=("$DOCS_APPCAST_PATH")
  if [[ -e "$DOCS_OLD_UPDATES_PATH" ]] || git ls-files -- "$DOCS_OLD_UPDATES_PATH" | grep -q .; then
    add_paths+=("$DOCS_OLD_UPDATES_PATH")
  fi

  git add -A "${add_paths[@]}"
  git commit -m "Update appcast for $TAG_NAME"
}

ensure_tag_at_head() {
  if git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null 2>&1; then
    local tag_commit
    tag_commit="$(git rev-list -n 1 "$TAG_NAME")"
    [[ "$tag_commit" == "$(git rev-parse HEAD)" ]] || fail "Tag $TAG_NAME already exists on a different commit."
    return
  fi

  git tag -a "$TAG_NAME" -m "Whitecat $VERSION"
}

load_github_auth() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    return
  fi

  local creds
  creds="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill)"
  GH_USER="$(printf '%s\n' "$creds" | sed -n 's/^username=//p')"
  GH_PASS="$(printf '%s\n' "$creds" | sed -n 's/^password=//p')"

  [[ -n "$GH_USER" ]] || fail "No GitHub username found in git credentials."
  [[ -n "$GH_PASS" ]] || fail "No GitHub password/token found in git credentials."
}

github_api() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsS \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "$@"
    return
  fi

  curl -fsS \
    -u "${GH_USER}:${GH_PASS}" \
    -H "Accept: application/vnd.github+json" \
    "$@"
}

upload_asset() {
  local release_json="$1"
  local api_url="$2"
  local asset_path="$3"
  local asset_name asset_id release_upload_url

  asset_name="$(basename "$asset_path")"
  asset_id="$(printf '%s' "$release_json" | jq -r --arg name "$asset_name" '.assets[]? | select(.name == $name) | .id' | head -n 1)"
  if [[ -n "$asset_id" ]]; then
    github_api -X DELETE "${api_url}/releases/assets/${asset_id}" >/dev/null
  fi

  release_upload_url="$(printf '%s' "$release_json" | jq -r '.upload_url // empty' | sed 's/{.*$//')"
  [[ -n "$release_upload_url" ]] || fail "GitHub release upload URL missing."

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsS \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "Content-Type: application/octet-stream" \
      --data-binary "@${asset_path}" \
      "${release_upload_url}?name=${asset_name}" >/dev/null
    return
  fi

  curl -fsS \
    -u "${GH_USER}:${GH_PASS}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${asset_path}" \
    "${release_upload_url}?name=${asset_name}" >/dev/null
}

publish_release() {
  local api_url="https://api.github.com/repos/${REPO_PATH}"
  local payload release_json release_id

  command -v jq >/dev/null || fail "jq is required to publish the GitHub Release."
  load_github_auth

  payload="$(jq -n \
    --arg tag "$TAG_NAME" \
    --arg name "$TAG_NAME" \
    --rawfile body "$RELEASE_BODY_PATH" \
    '{tag_name: $tag, name: $name, body: $body, draft: false, prerelease: false}')"

  release_json="$(github_api "${api_url}/releases/tags/${TAG_NAME}" 2>/dev/null || true)"
  release_id="$(printf '%s' "$release_json" | jq -r '.id // empty')"
  if [[ -n "$release_id" ]]; then
    release_json="$(github_api \
      -H "Content-Type: application/json" \
      -X PATCH \
      "${api_url}/releases/${release_id}" \
      -d "$payload")"
  else
    release_json="$(github_api \
      -H "Content-Type: application/json" \
      -X POST \
      "${api_url}/releases" \
      -d "$payload")"
  fi

  release_id="$(printf '%s' "$release_json" | jq -r '.id // empty')"
  [[ -n "$release_id" ]] || fail "GitHub release creation failed."

  upload_asset "$release_json" "$api_url" "$ZIP_PATH"
  upload_asset "$release_json" "$api_url" "$DMG_PATH"
  upload_asset "$release_json" "$api_url" "$RELEASES_DIR/appcast.xml"

  RELEASE_URL="$(printf '%s' "$release_json" | jq -r '.html_url // empty')"
  [[ -n "$RELEASE_URL" ]] || fail "GitHub release URL missing."
}

if [[ "$DRY_RUN" == "1" ]]; then
  cat <<EOF
Dry run complete.
Version: $VERSION
Build: $BUILD_NUMBER
Tag: $TAG_NAME

Files to upload:
  ZIP:     $ZIP_PATH
  DMG:     $DMG_PATH
  Appcast: $DOCS_APPCAST_PATH
  Notes:   $RELEASES_DIR/${APP_NAME}-${VERSION}.txt
EOF
  exit 0
fi

commit_feed_if_needed
ensure_tag_at_head

git push origin "$TAG_NAME"
publish_release
git push origin main

cat <<EOF
Release published.
Version:     $VERSION
Build:       $BUILD_NUMBER
Tag:         $TAG_NAME
Release:     $RELEASE_URL

Uploaded files:
  ZIP:       $ZIP_PATH  (SHA-256: $ZIP_SHA)
  DMG:       $DMG_PATH  (SHA-256: $DMG_SHA)
  Appcast:   $DOCS_APPCAST_PATH
  Notes:     $RELEASES_DIR/${APP_NAME}-${VERSION}.txt
EOF
