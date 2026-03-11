#!/bin/zsh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./Scripts/release.sh <version>

Example:
  ./Scripts/release.sh 0.1.6

This script:
  1. Validates the version format.
  2. Requires a clean local main branch.
  3. Creates an annotated git tag v<version>.
  4. Pushes the tag to origin, which triggers the GitHub release workflow.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

VERSION="${1#v}"
TAG="v$VERSION"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Version must use semantic versioning, for example 0.1.6" >&2
  exit 1
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "Release tags must be created from the local main branch." >&2
  exit 1
fi

if [[ -n "$(git status --short)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before releasing." >&2
  exit 1
fi

git fetch origin main --tags >/dev/null

ahead_behind="$(git rev-list --left-right --count origin/main...main)"
if [[ "$ahead_behind" != "0	0" ]]; then
  echo "Local main is not in sync with origin/main. Pull or push before releasing." >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Tag $TAG already exists locally." >&2
  exit 1
fi

if git ls-remote --tags origin "refs/tags/$TAG" | grep -q .; then
  echo "Tag $TAG already exists on origin." >&2
  exit 1
fi

git tag -a "$TAG" -m "Whitecat $VERSION"
git push origin "$TAG"

cat <<EOF
Created and pushed $TAG.
GitHub Actions will now build the signed app, create the GitHub Release, and publish the new appcast.
EOF
