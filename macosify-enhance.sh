#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT="MacOSify"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"
mkdir -p "$STATE_DIR"

info(){ printf '[MacOSify] %s\n' "$*"; }
warn(){ printf '[MacOSify][WARN] %s\n' "$*" >&2; }

[[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* || -n "${GNOME_SHELL_SESSION_MODE:-}" ]] || { warn 'GNOME session not detected; enhancement skipped.'; exit 0; }
command -v curl >/dev/null || { warn 'curl unavailable; enhancement skipped.'; exit 0; }
command -v gnome-extensions >/dev/null || { warn 'gnome-extensions unavailable; enhancement skipped.'; exit 0; }
command -v python3 >/dev/null || { warn 'python3 unavailable; enhancement skipped.'; exit 0; }

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
except Exception: pass
PY
}

install_ego(){
  local uuid="$1" shell="${2:-50}" zip="$STATE_DIR/${1}.zip" url
  url="$(curl -fsSL --retry 3 --connect-timeout 15 "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("download_url",""))')" || return 1
  [[ -n "$url" ]] || return 1
  curl -fL --retry 3 --connect-timeout 15 -o "$zip" "https://extensions.gnome.org${url}"
  gnome-extensions install --force "$zip" >/dev/null
  rm -f "$zip"
  gnome-extensions enable "$uuid" 2>/dev/null || true
  persist "$uuid"
}

info 'Applying GNOME 50 Tahoe panel enhancements'

# macOS-style global application menu. Version 15 is the active GNOME 50 build.
install_ego 'globalmenu@ShiroOSL.github.io' 50 || warn 'Global Menu could not be installed.'

# macOS-inspired quick-settings/control-center enhancements.
install_ego 'kiwi@kemma' 50 || warn 'Kiwi quick-settings enhancement could not be installed.'

# Load MacTahoe shell theme from ~/.themes.
install_ego 'user-theme@gnome-shell-extensions.gcampax.github.com' 50 || warn 'User Themes could not be installed.'

gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-Light' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'MacTahoe' 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-theme 'MacTahoe-cursors' 2>/dev/null || true
dconf write /org/gnome/shell/extensions/user-theme/name "'MacTahoe-Light'" 2>/dev/null || true

# GNOME 50-compatible Hide Top Bar, configured to reveal on pointer-at-top.
if install_ego 'hidetopbar@mathieu.bidon.ca' 50; then
  dconf write /org/gnome/shell/extensions/hidetopbar/enable-intellihide true 2>/dev/null || true
  dconf write /org/gnome/shell/extensions/hidetopbar/mouse-sensitive true 2>/dev/null || true
  dconf write /org/gnome/shell/extensions/hidetopbar/mouse-sensitive-area 3 2>/dev/null || true
  dconf write /org/gnome/shell/extensions/hidetopbar/animation-time-autohide 0.20 2>/dev/null || true
  dconf write /org/gnome/shell/extensions/hidetopbar/animation-time-show 0.20 2>/dev/null || true
else
  warn 'Hide Top Bar could not be installed.'
fi

# Dash2Dock Animated v92: app launcher first, favorites in the middle, trash last.
dconf write /org/gnome/shell/extensions/dash2dock-lite/dock-position "'BOTTOM'" 2>/dev/null || true
dconf write /org/gnome/shell/extensions/dash2dock-lite/autohide true 2>/dev/null || true
dconf write /org/gnome/shell/extensions/dash2dock-lite/intellihide true 2>/dev/null || true
dconf write /org/gnome/shell/extensions/dash2dock-lite/icon-size 48 2>/dev/null || true
dconf write /org/gnome/shell/extensions/dash2dock-lite/apps-icon true 2>/dev/null || true
dconf write /org/gnome/shell/extensions/dash2dock-lite/apps-icon-front true 2>/dev/null || true
dconf write /org/gnome/shell/extensions/dash2dock-lite/trash-icon true 2>/dev/null || true
dconf write /org/gnome/shell/extensions/dash2dock-lite/favorites-only false 2>/dev/null || true

# Never run Ubuntu Dock alongside Dash2Dock Animated.
gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null || true

info 'Enhancement stage complete. Log out/in or reboot once to activate the new GNOME Shell extensions.'
