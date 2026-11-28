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
ICON_ASSET="spectrum-configurator.png"
tmp=""
CURL=(curl --proto '=https' --tlsv1.2 -fsSL)

# Embedded so the file installed as root is exactly what this script says, not whatever the download returns.
# tests/embedded-rule.sh checks that it equals packaging/70-spectrum-configurator.rules.
udev_rule() {
  cat <<'RULE'
# Lets the logged-in user open the mouse's vendor interface (interface 1).
# The pointer interface (interface 0) is not matched.
# Matches on ID_* properties, not ATTRS{}: ATTRS keys in one rule must all match the same
# parent device, and the vendor/product IDs and the interface number sit on different parents.
SUBSYSTEM=="hidraw", ENV{ID_VENDOR_ID}=="30fa", ENV{ID_MODEL_ID}=="1440", ENV{ID_USB_INTERFACE_NUM}=="01", MODE="0660", TAG+="uaccess"
RULE
}

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

# Best effort: lets the app menu and icon theme notice the new files without a re-login.
refresh_caches() {
  if command -v update-desktop-database >/dev/null; then
    update-desktop-database -q "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true
  fi
  if command -v gtk-update-icon-cache >/dev/null && [ -f "$DATA_HOME/icons/hicolor/index.theme" ]; then
    gtk-update-icon-cache -q -t -f "$DATA_HOME/icons/hicolor" 2>/dev/null || true
  fi
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
  refresh_caches
  if [ ! -e "$UDEV_RULE" ]; then
    :
  elif [ "$(cat "$UDEV_RULE")" = "$(udev_rule)" ]; then
    echo "Removing the udev rule needs root, so sudo may ask for your password."
    as_root rm -f "$UDEV_RULE"
    reload_udev
  else
    echo "Leaving $UDEV_RULE in place: it is not the file this installer wrote."
  fi
  echo "Spectrum Configurator is uninstalled."
}

install_app() {
  # Not local: the EXIT trap runs after this function has returned.
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  echo "Downloading Spectrum Configurator..."
  local file
  for file in "$ASSET" "$ICON_ASSET" SHA256SUMS; do
    "${CURL[@]}" "$BASE_URL/$file" -o "$tmp/$file" || die "could not download $file from $BASE_URL"
  done
  # SHA256SUMS also lists the udev rule, which is embedded here and not downloaded, so missing files are
  # ignored by --check. That is why both downloads must be required to be listed first.
  for file in "$ASSET" "$ICON_ASSET"; do
    grep -qE "^[0-9a-f]{64}  $file\$" "$tmp/SHA256SUMS" || die "$file is not in SHA256SUMS, nothing was installed"
  done
  (cd "$tmp" && sha256sum --check --quiet --ignore-missing SHA256SUMS) || die "checksum mismatch, nothing was installed"

  mkdir -p "$APP_DIR" "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON_FILE")"
  install -m 755 "$tmp/$ASSET" "$APPIMAGE"
  install -m 644 "$tmp/$ICON_ASSET" "$ICON_FILE"
  cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Spectrum Configurator
Comment=Configuration app for the Cosmic Byte Spectrum mouse
Exec="$APPIMAGE"
Icon=spectrum-configurator
StartupWMClass=spectrum-configurator
Categories=Utility;Settings;
Terminal=false
EOF

  refresh_caches

  echo "The udev rule lets your user open the mouse. It is the only step that needs root,"
  echo "so sudo may ask for your password."
  # Piped, not passed as a file: a file in a user-writable directory could be swapped while sudo asks for the password.
  udev_rule | as_root install -m 644 /dev/stdin "$UDEV_RULE"
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
