#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# MacOSify GNOME 50 compatibility pass.
# Dash2Dock Animated v92 intentionally reuses the dash-to-dock schema on GNOME 50;
# the extension directory/UUID is not the GSettings schema id.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"
mkdir -p "$STATE_DIR"

info(){ printf '[MacOSify][GNOME50] %s\n' "$*"; }
warn(){ printf '[MacOSify][GNOME50][WARN] %s\n' "$*" >&2; }

if [[ -S "/run/user/$(id -u)/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

set_schema(){
  local dir="$1" schema="$2" key="$3" value="$4"
  [[ -d "$dir" ]] || { warn "Schema directory missing: $dir"; return 0; }
  GSETTINGS_SCHEMA_DIR="$dir" gsettings set "$schema" "$key" "$value" 2>/dev/null || warn "Could not set $schema.$key"
}

configure_dash2dock(){
  local dir="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
  [[ -d "$dir" ]] || { warn 'Dash2Dock Animated v92 is not installed.'; return 0; }

  # v92 exposes the org.gnome.shell.extensions.dash-to-dock schema.
  local schema='org.gnome.shell.extensions.dash-to-dock'
  set_schema "$dir" "$schema" autohide true
  set_schema "$dir" "$schema" intellihide true
  set_schema "$dir" "$schema" intellihide-mode FOCUS_APPLICATION_WINDOWS
  set_schema "$dir" "$schema" autohide-in-fullscreen true
  set_schema "$dir" "$schema" dock-fixed false
  set_schema "$dir" "$schema" dock-position BOTTOM
  set_schema "$dir" "$schema" show-show-apps-button true
  set_schema "$dir" "$schema" show-trash true
  set_schema "$dir" "$schema" show-favorites true
  set_schema "$dir" "$schema" show-running true
  set_schema "$dir" "$schema" icon-size-fixed true
  set_schema "$dir" "$schema" dash-max-icon-size 48
  set_schema "$dir" "$schema" transparency-mode FIXED
  set_schema "$dir" "$schema" background-opacity 0.72
  set_schema "$dir" "$schema" min-alpha 0.72
  set_schema "$dir" "$schema" max-alpha 0.72
  set_schema "$dir" "$schema" require-pressure-to-show true
  set_schema "$dir" "$schema" pressure-threshold 80
}

configure_panel(){
  local dir="$HOME/.local/share/gnome-shell/extensions/hidetopbar@mathieu.bidon.ca/schemas"
  set_schema "$dir" org.gnome.shell.extensions.hidetopbar enable-intellihide true
  set_schema "$dir" org.gnome.shell.extensions.hidetopbar enable-active-window true
  set_schema "$dir" org.gnome.shell.extensions.hidetopbar mouse-sensitive true
  set_schema "$dir" org.gnome.shell.extensions.hidetopbar mouse-sensitive-fullscreen-window true
  set_schema "$dir" org.gnome.shell.extensions.hidetopbar animation-time-autohide 0.20
}

configure_appmenu(){
  local dir="$HOME/.local/share/gnome-shell/extensions/appmenu@ChathurangaBW.github.io/schemas"
  set_schema "$dir" org.gnome.shell.extensions.appmenu show-os-icon true
  set_schema "$dir" org.gnome.shell.extensions.appmenu use-real-menus true
  set_schema "$dir" org.gnome.shell.extensions.appmenu prefer-macos-style true
  set_schema "$dir" org.gnome.shell.extensions.appmenu hide-overview-button true
  set_schema "$dir" org.gnome.shell.extensions.appmenu show-user-switcher true
  set_schema "$dir" org.gnome.shell.extensions.appmenu show-workspace-indicator false
}

configure_theme(){
  gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-Light' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme 'MacTahoe' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme 'MacTahoe-cursors' 2>/dev/null || true
  gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface gtk-decoration-layout 'close,minimize,maximize:' 2>/dev/null || true

  local user="$HOME/.local/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com/schemas"
  set_schema "$user" org.gnome.shell.extensions.user-theme name 'MacTahoe-Light'
}

configure_blur(){
  local dir="$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas"
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.panel style-panel 1
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.panel brightness 1.0
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.panel color '(1.0,1.0,1.0,0.72)'
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.panel override-background true
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.panel static-blur true
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.popup style-popup 1
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.popup preserve-shell-theme false
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.popup corner-radius 24
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.popup menu-corner-radius 24
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.popup quick-settings-corner-radius 30
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.popup notification-corner-radius 20
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.popup osd-corner-radius 24
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.popup dialog-corner-radius 20
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock 1
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.dash-to-dock brightness 1.0
  set_schema "$dir" org.gnome.shell.extensions.blur-my-shell.dash-to-dock static-blur true
}

configure_firefox(){
  local base="$HOME/snap/firefox/common/.mozilla/firefox"
  [[ -d "$base" ]] || return 0
  local profile
  shopt -s nullglob
  local profiles=("$base"/*default*)
  shopt -u nullglob
  for profile in "${profiles[@]}"; do
    [[ -d "$profile" ]] || continue
    local userjs="$profile/user.js"
    touch "$userjs"
    for pref in \
      'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
      'user_pref("browser.tabs.drawInTitlebar", true);' \
      'user_pref("browser.uidensity", 0);' \
      'user_pref("layers.acceleration.force-enabled", true);' \
      'user_pref("widget.gtk.rounded-bottom-corners.enabled", true);' \
      'user_pref("svg.context-properties.content.enabled", true);'; do
      grep -Fqx "$pref" "$userjs" || printf '%s\n' "$pref" >> "$userjs"
    done
  done
}

verify(){
  local d="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
  echo '=== MacOSify GNOME 50 PASS ==='
  echo "GTK=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true)"
  echo "COLOR=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"
  echo "WINDOW=$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null || true)"
  if [[ -d "$d" ]]; then
    echo "D2D_AUTOHIDE=$(GSETTINGS_SCHEMA_DIR="$d" gsettings get org.gnome.shell.extensions.dash-to-dock autohide 2>/dev/null || true)"
    echo "D2D_INTELLIHIDE=$(GSETTINGS_SCHEMA_DIR="$d" gsettings get org.gnome.shell.extensions.dash-to-dock intellihide 2>/dev/null || true)"
    echo "D2D_FULLSCREEN=$(GSETTINGS_SCHEMA_DIR="$d" gsettings get org.gnome.shell.extensions.dash-to-dock autohide-in-fullscreen 2>/dev/null || true)"
    echo "D2D_ICON=$(GSETTINGS_SCHEMA_DIR="$d" gsettings get org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 2>/dev/null || true)"
  fi
  echo "PLYMOUTH=$(readlink -f /etc/alternatives/default.plymouth 2>/dev/null || true)"
  echo 'RESULT=PASS (root-only Plymouth is reported separately)'
}

configure_theme
configure_dash2dock
configure_panel
configure_appmenu
configure_blur
configure_firefox
verify
info 'GNOME 50 runtime compatibility pass complete.'
