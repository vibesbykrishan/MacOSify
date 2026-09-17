#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

THEMES=(
  MacTahoe-Light
  MacTahoe-Dark
  MacTahoe-Light-blue
  MacTahoe-Light-purple
  MacTahoe-Light-pink
  MacTahoe-Light-red
  MacTahoe-Light-orange
  MacTahoe-Light-yellow
  MacTahoe-Light-green
  MacTahoe-Light-grey
  MacTahoe-Dark-blue
  MacTahoe-Dark-purple
  MacTahoe-Dark-pink
  MacTahoe-Dark-red
  MacTahoe-Dark-orange
  MacTahoe-Dark-green
  MacTahoe-Dark-yellow
  MacTahoe-Dark-grey
)

SCHEMA_ROOT="$HOME/.local/share/gnome-shell/extensions"
USER_THEME_SCHEMA="$SCHEMA_ROOT/user-theme@gnome-shell-extensions.gcampax.github.com/schemas"
BLUR_SCHEMA="$SCHEMA_ROOT/blur-my-shell@aunetx/schemas"
DOCK_SCHEMA="$SCHEMA_ROOT/dash2dock-lite@icedman.github.com/schemas"
THEME_ROOT="$HOME/.themes"

bus(){
  if [[ -S "/run/user/$(id -u)/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
  fi
}

set_schema(){
  local dir="$1" schema="$2" key="$3" value="$4"
  [[ -d "$dir" ]] || return 0
  GSETTINGS_SCHEMA_DIR="$dir" gsettings set "$schema" "$key" "$value" 2>/dev/null || true
}

patch_shell(){
  local theme="$1" file="$THEME_ROOT/$theme/gnome-shell/gnome-shell.css" marker='/* MacOSify Tahoe Liquid Glass v1.8 */'
  [[ -f "$file" ]] || return 0
  grep -Fq "$marker" "$file" && return 0
  if [[ "$theme" == *Dark* ]]; then
    cat >>"$file" <<'CSS'

/* MacOSify Tahoe Liquid Glass v1.8 */
#panel { background-color: rgba(28,28,30,0.82) !important; color: #f5f5f7 !important; }
#panel .panel-corner { -panel-corner-background-color: rgba(28,28,30,0.82) !important; }
#panel .panel-button { color: #f5f5f7 !important; }
#panel .panel-button:hover, #panel .panel-button:active, #panel .panel-button:checked { color: #ffffff !important; }
.popup-menu-content { background-color: rgba(38,38,40,0.94) !important; border-radius: 24px !important; }
.popup-menu-boxpointer { -arrow-border-radius: 24px !important; }
CSS
  else
    cat >>"$file" <<'CSS'

/* MacOSify Tahoe Liquid Glass v1.8 */
#panel { background-color: rgba(254,254,254,0.75) !important; color: #424242 !important; }
#panel .panel-corner { -panel-corner-background-color: rgba(254,254,254,0.75) !important; }
#panel .panel-button { color: #424242 !important; }
#panel .panel-button:hover, #panel .panel-button:active, #panel .panel-button:checked { color: #202020 !important; }
.popup-menu-content { background-color: rgba(254,254,254,0.94) !important; border-radius: 24px !important; }
.popup-menu-boxpointer { -arrow-border-radius: 24px !important; }
CSS
  fi
}

apply_theme(){
  local theme="$1" color='prefer-light'
  [[ -d "$THEME_ROOT/$theme" ]] || { echo "Theme not installed: $theme" >&2; exit 1; }
  [[ "$theme" == *Dark* ]] && color='prefer-dark'
  bus
  gsettings set org.gnome.desktop.interface gtk-theme "$theme"
  gsettings set org.gnome.desktop.interface color-scheme "$color" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme MacTahoe 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme MacTahoe-cursors 2>/dev/null || true
  set_schema "$USER_THEME_SCHEMA" org.gnome.shell.extensions.user-theme name "$theme"
  patch_shell "$theme"
  if [[ "$color" == prefer-light ]]; then
    set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.panel style-panel 1
    set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.panel brightness 1.0
    set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.panel color '(1.0,1.0,1.0,0.72)'
    set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.popup style-popup 1
    set_schema "$DOCK_SCHEMA" org.gnome.shell.extensions.dash2dock-lite background-color '(1.0,1.0,1.0,0.72)'
  else
    set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.panel style-panel 2
    set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.panel brightness 1.0
    set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.panel color '(0.08,0.08,0.09,0.82)'
    set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.popup style-popup 2
    set_schema "$DOCK_SCHEMA" org.gnome.shell.extensions.dash2dock-lite background-color '(0.08,0.08,0.09,0.78)'
  fi
  set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.popup corner-radius 24
  set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.popup menu-corner-radius 24
  set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.popup quick-settings-corner-radius 30
  set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.popup notification-corner-radius 20
  set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.popup osd-corner-radius 24
  set_schema "$BLUR_SCHEMA" org.gnome.shell.extensions.blur-my-shell.popup dialog-corner-radius 20
  set_schema "$DOCK_SCHEMA" org.gnome.shell.extensions.dash2dock-lite blur-background true
  set_schema "$DOCK_SCHEMA" org.gnome.shell.extensions.dash2dock-lite border-radius 28
  set_schema "$DOCK_SCHEMA" org.gnome.shell.extensions.dash2dock-lite border-thickness 0
  echo "MacOSify theme applied: $theme"
}

list_themes(){
  for theme in "${THEMES[@]}"; do [[ -d "$THEME_ROOT/$theme" ]] && printf '%s\n' "$theme"; done
}

gui(){
  if command -v zenity >/dev/null 2>&1; then
    local choice
    choice="$(list_themes | zenity --list --title='MacOSify Theme Center' --text='Choose a MacTahoe theme' --column='Theme' --width=420 --height=520 2>/dev/null || true)"
    [[ -n "$choice" ]] && apply_theme "$choice"
    exit 0
  fi
  menu
}

menu(){
  mapfile -t available < <(list_themes)
  ((${#available[@]})) || { echo 'No MacTahoe themes found.' >&2; exit 1; }
  echo 'MacOSify Theme Center'
  local i=1
  for theme in "${available[@]}"; do echo "  $i) $theme"; ((i++)); done
  read -r -p 'Select theme: ' n
  [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#available[@]} )) || exit 1
  apply_theme "${available[n-1]}"
}

case "${1:---gui}" in
  --gui|gui|change) gui ;;
  list|--list) list_themes ;;
  light) apply_theme MacTahoe-Light ;;
  dark) apply_theme MacTahoe-Dark ;;
  set) [[ -n "${2:-}" ]] || { echo 'Usage: macosify-theme set THEME'; exit 2; }; apply_theme "$2" ;;
  *) echo 'Usage: macosify-theme [change|gui|list|light|dark|set THEME]'; exit 2 ;;
esac
