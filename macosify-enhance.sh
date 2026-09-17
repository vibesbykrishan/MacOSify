#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT="MacOSify"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"
mkdir -p "$STATE_DIR"

info(){ printf '[MacOSify] %s\n' "$*"; }
warn(){ printf '[MacOSify][WARN] %s\n' "$*" >&2; }

# Desktop Commander/SSH may not export the session bus even while GNOME is running.
if [[ -S "/run/user/$(id -u)/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

command -v curl >/dev/null || { warn 'curl unavailable; enhancement skipped.'; exit 0; }
command -v gnome-extensions >/dev/null || { warn 'gnome-extensions unavailable; enhancement skipped.'; exit 0; }
command -v python3 >/dev/null || { warn 'python3 unavailable; enhancement skipped.'; exit 0; }
command -v git >/dev/null || { warn 'git unavailable; enhancement skipped.'; exit 0; }

persist(){
  local uuid="$1"
  python3 - "$uuid" <<'PY'
import ast, subprocess, sys
u=sys.argv[1]
try:
    raw=subprocess.check_output(['gsettings','get','org.gnome.shell','enabled-extensions'], text=True).strip()
    xs=ast.literal_eval(raw)
    if u not in xs: xs.append(u)
    subprocess.run(['gsettings','set','org.gnome.shell','enabled-extensions',str(xs)], check=False)
except Exception:
    pass
PY
}

install_ego(){
  local uuid="$1" shell="${2:-50}" zip="$STATE_DIR/${uuid}.zip" url
  url="$(curl -fsSL --retry 3 --connect-timeout 15 "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("download_url",""))')" || return 1
  [[ -n "$url" ]] || return 1
  curl -fL --retry 3 --connect-timeout 15 -o "$zip" "https://extensions.gnome.org${url}"
  gnome-extensions install --force "$zip" >/dev/null
  rm -f "$zip"
  gnome-extensions enable "$uuid" 2>/dev/null || true
  persist "$uuid"
}

info 'Applying GNOME 50 Tahoe panel enhancements'

# Modern zero-dependency macOS global menu; supports GNOME 45-50 and Wayland.
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/macosify/sources/AppMenu"
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" fetch --depth=1 origin >/dev/null 2>&1 || true
  git -C "$APP_DIR" reset --hard origin/HEAD >/dev/null 2>&1 || true
else
  git clone --depth=1 https://github.com/ChathurangaBW/AppMenu.git "$APP_DIR"
fi
bash "$APP_DIR/install.sh" --clean-stale
persist 'appmenu@ChathurangaBW.github.io'

# macOS-inspired quick settings/control-center enhancements.
install_ego 'kiwi@kemma' 50 || warn 'Kiwi quick-settings enhancement could not be installed.'

# Apply the MacTahoe light shell theme.
install_ego 'user-theme@gnome-shell-extensions.gcampax.github.com' 50 || warn 'User Themes could not be installed.'
gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-Light' 2>/dev/null || gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-light' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'MacTahoe' 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-theme 'MacTahoe-cursors' 2>/dev/null || true

# GNOME 50-compatible Hide Top Bar: auto-hide and reveal when the pointer reaches the top.
if install_ego 'hidetopbar@mathieu.bidon.ca' 50; then
  HIDE_SCHEMA="$HOME/.local/share/gnome-shell/extensions/hidetopbar@mathieu.bidon.ca/schemas"
  GSETTINGS_SCHEMA_DIR="$HIDE_SCHEMA" gsettings set org.gnome.shell.extensions.hidetopbar enable-intellihide true 2>/dev/null || true
  GSETTINGS_SCHEMA_DIR="$HIDE_SCHEMA" gsettings set org.gnome.shell.extensions.hidetopbar mouse-sensitive true 2>/dev/null || true
  GSETTINGS_SCHEMA_DIR="$HIDE_SCHEMA" gsettings set org.gnome.shell.extensions.hidetopbar animation-time-autohide 0.20 2>/dev/null || true
fi

# Dash2Dock Animated: launcher first, favorites, trash last, with auto/intellihide.
D2D_SCHEMA="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
if [[ -d "$D2D_SCHEMA" ]]; then
  GSETTINGS_SCHEMA_DIR="$D2D_SCHEMA" gsettings set org.gnome.shell.extensions.dash2dock-lite apps-icon true 2>/dev/null || true
  GSETTINGS_SCHEMA_DIR="$D2D_SCHEMA" gsettings set org.gnome.shell.extensions.dash2dock-lite apps-icon-front true 2>/dev/null || true
  GSETTINGS_SCHEMA_DIR="$D2D_SCHEMA" gsettings set org.gnome.shell.extensions.dash2dock-lite trash-icon true 2>/dev/null || true
  GSETTINGS_SCHEMA_DIR="$D2D_SCHEMA" gsettings set org.gnome.shell.extensions.dash2dock-lite autohide-dash true 2>/dev/null || true
  GSETTINGS_SCHEMA_DIR="$D2D_SCHEMA" gsettings set org.gnome.shell.extensions.dash2dock-lite autohide-dodge true 2>/dev/null || true
  GSETTINGS_SCHEMA_DIR="$D2D_SCHEMA" gsettings set org.gnome.shell.extensions.dash2dock-lite icon-size 48 2>/dev/null || true
fi

# Never run Ubuntu Dock alongside Dash2Dock Animated.
gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null || true

info 'Enhancement stage complete. Log out/in or reboot once to activate the new GNOME Shell extensions.'
