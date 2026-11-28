#!/usr/bin/env bash
# Prints the next patch version if Dependabot has changed the app's dependencies since the latest tag.
# Prints nothing otherwise. Used by .github/workflows/auto-release.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

last=$(git tag --list 'v*' --sort=-v:refname | head -n 1)
[ -n "$last" ] || { echo "No version tag found" >&2; exit 1; }

updates=$(git log --oneline --author='dependabot\[bot\]' "$last..HEAD" -- \
  package.json package-lock.json src-tauri/Cargo.toml src-tauri/Cargo.lock)
[ -n "$updates" ] || exit 0

IFS=. read -r major minor patch <<<"${last#v}"
echo "$major.$minor.$((patch + 1))"
