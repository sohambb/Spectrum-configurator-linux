#!/usr/bin/env bash
# Installs Spectrum Configurator for the current user. Uninstall with: install.sh --uninstall
set -euo pipefail

REPO="sohambb/Spectrum-configurator-linux"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA_HOME/spectrum-configurator"
APPIMAGE="$APP_DIR/Spectrum-Configurator.AppImage"
DESKTOP_FILE="$DATA_HOME/applications/spectrum-configurator.desktop"
ICON_FILE="$DATA_HOME/icons/hicolor/128x128/apps/spectrum-configurator.png"
UDEV_RULE="/etc/udev/rules.d/70-spectrum-configurator.rules"
ASSET="Spectrum-Configurator-x86_64.AppImage"
RULE_ASSET="70-spectrum-configurator.rules"
ICON_ASSET="spectrum-configurator.png"
tmp=""

die() {
  echo "Error: $*" >&2
  exit 1
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

reload_udev() {
  as_root udevadm control --reload-rules && as_root udevadm trigger ||
    echo "Warning: could not reload udev. Unplug and replug the mouse, or reboot." >&2
}

fuse_package() {
  (
    # shellcheck source=/dev/null
    . /etc/os-release
    case " ${ID:-} ${ID_LIKE:-} " in
      *" arch "*) echo "fuse2" ;;
      *" fedora "*) echo "fuse-libs" ;;
      *) echo "libfuse2 (libfuse2t64 on Ubuntu 24.04 and newer)" ;;
    esac
  )
}

uninstall() {
  rm -f "$APPIMAGE" "$DESKTOP_FILE" "$ICON_FILE"
  rmdir "$APP_DIR" 2>/dev/null || true
  if [ -e "$UDEV_RULE" ]; then
    echo "Removing the udev rule needs root, so sudo may ask for your password."
    as_root rm -f "$UDEV_RULE"
    reload_udev
  fi
  echo "Spectrum Configurator is uninstalled."
}

install_app() {
  # Not local: the EXIT trap runs after this function has returned.
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  echo "Downloading Spectrum Configurator..."
  local file
  for file in "$ASSET" "$RULE_ASSET" "$ICON_ASSET" SHA256SUMS; do
    curl -fsSL "$BASE_URL/$file" -o "$tmp/$file" || die "could not download $file from $BASE_URL"
  done
  (cd "$tmp" && sha256sum --check --quiet SHA256SUMS) || die "checksum mismatch, nothing was installed"

  mkdir -p "$APP_DIR" "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON_FILE")"
  install -m 755 "$tmp/$ASSET" "$APPIMAGE"
  install -m 644 "$tmp/$ICON_ASSET" "$ICON_FILE"
  cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Spectrum Configurator
Comment=Configuration app for the Cosmic Byte Spectrum mouse
Exec=$APPIMAGE
Icon=spectrum-configurator
StartupWMClass=spectrum-configurator
Categories=Utility;Settings;
Terminal=false
EOF

  echo "The udev rule lets your user open the mouse. It is the only step that needs root,"
  echo "so sudo may ask for your password."
  as_root install -m 644 "$tmp/$RULE_ASSET" "$UDEV_RULE"
  reload_udev

  echo "Installed. Open Spectrum Configurator from the app menu."
  echo "If the mouse is plugged in, unplug and replug it once so the rule applies."
}

main() {
  if [ "${1:-}" = "--uninstall" ]; then
    uninstall
    return
  fi
  [ "$#" -eq 0 ] || die "unknown option: $1 (the only option is --uninstall)"
  [ "$(uname -m)" = "x86_64" ] || die "only x86_64 is supported, this machine is $(uname -m)"
  [ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root. It uses sudo only for the udev rule"
  command -v curl >/dev/null || die "curl is required"
  command -v sha256sum >/dev/null || die "sha256sum is required"
  command -v sudo >/dev/null || die "sudo is required to install the udev rule"
  # Captured first: with pipefail, grep -q closing the pipe early would look like a failure.
  local libs
  libs=$(PATH="$PATH:/sbin:/usr/sbin" ldconfig -p 2>/dev/null || true)
  grep -q 'libfuse\.so\.2' <<<"$libs" || die "AppImages need FUSE 2. Install the package $(fuse_package) and run this again"
  install_app
}

main "$@"
