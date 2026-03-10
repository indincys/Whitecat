#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ROOT_DIR/Configs/Whitecat.entitlements.template"
OUTPUT_PATH="${1:-$ROOT_DIR/Configs/Whitecat.entitlements}"
TEAM_BUNDLE_PREFIX="${TEAM_BUNDLE_PREFIX:?TEAM_BUNDLE_PREFIX is required}"

sed "s#__TEAM_BUNDLE_PREFIX__#$TEAM_BUNDLE_PREFIX#g" "$TEMPLATE" > "$OUTPUT_PATH"
echo "$OUTPUT_PATH"
