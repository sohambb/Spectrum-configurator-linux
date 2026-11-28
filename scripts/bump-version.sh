#!/usr/bin/env bash
# Sets the app version everywhere it is stored. Usage: scripts/bump-version.sh 1.2.3
set -euo pipefail
cd "$(dirname "$0")/.."

new=${1:-}
[[ $new =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: $0 <major.minor.patch>" >&2; exit 1; }

npm version "$new" --no-git-tag-version --allow-same-version >/dev/null
sed -i "s/^  \"version\": \"[^\"]*\"/  \"version\": \"$new\"/" src-tauri/tauri.conf.json
sed -i "0,/^version = /s/^version = .*/version = \"$new\"/" src-tauri/Cargo.toml
# Only the app's own entry: other crates in the lockfile can have the same version number.
sed -i "/^name = \"spectrum-configurator\"\$/{n;s/.*/version = \"$new\"/}" src-tauri/Cargo.lock

for found in "$(jq -r .version package.json)" "$(jq -r '.packages[""].version' package-lock.json)" \
  "$(jq -r .version src-tauri/tauri.conf.json)" "$(sed -n 's/^version = "\(.*\)"/\1/p' src-tauri/Cargo.toml | head -n 1)" \
  "$(sed -n '/^name = "spectrum-configurator"$/{n;s/^version = "\(.*\)"/\1/p}' src-tauri/Cargo.lock)"; do
  [ "$found" = "$new" ] || { echo "A file still has version '$found' instead of $new" >&2; exit 1; }
done
echo "Version set to $new"
