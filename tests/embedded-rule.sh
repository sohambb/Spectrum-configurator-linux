#!/usr/bin/env bash
# Fails if the udev rule embedded in install.sh differs from packaging/70-spectrum-configurator.rules.
set -euo pipefail
cd "$(dirname "$0")/.."
embedded=$(awk "/^  cat <<'RULE'\$/{f=1;next} /^RULE\$/{f=0} f" install.sh)
[ -n "$embedded" ] || { echo "No embedded rule found in install.sh" >&2; exit 1; }
if diff <(printf '%s\n' "$embedded") packaging/70-spectrum-configurator.rules; then
  echo "Embedded udev rule matches packaging/70-spectrum-configurator.rules"
else
  echo "install.sh and packaging/70-spectrum-configurator.rules differ" >&2
  exit 1
fi
