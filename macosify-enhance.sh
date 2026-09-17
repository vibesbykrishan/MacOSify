#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT="MacOSify"
MACOSIFY_VERSION="1.7.0"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"
SOURCE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/macosify/sources"
mkdir -p "$STATE_DIR" "$SOURCE_DIR"

info(){ printf '[MacOSify] %s\n' "$*"; }
warn(){ printf '[MacOSify][WARN] %s\n' "$*" >&2; }

if [[ -S "/run/user/$(id -u)/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

for cmd in curl gnome-extensions python3 git; do
  command -v "$cmd" >/dev/null || { warn "$cmd unavailable; enhancement skipped."; exit 0; }
done

set_schema(){
  local dir="$1" schema="$2" key="$3" value="$4"
  [[ -d "$dir" ]] || return 0
  GSETTINGS_SCHEMA_DIR="$dir" gsettings set "$schema" "$key" "$value" 2>/dev/null || true
}

persist_extensions(){
  python3 <<'PY'
import ast, subprocess
keep = {
    'tiling-assistant@ubuntu.com',
    'blur-my-shell@aunetx',
    'appindicatorsupport@rgcjonas.gmail.com',
    'kiwi@kemma',
    'user-theme@gnome-shell-extensions.gcampax.github.com',
    'hidetopbar@mathieu.bidon.ca',
    'dash2dock-lite@icedman.github.com',
    'appmenu@ChathurangaBW.github.io',
}
stale = {
    'ubuntu-dock@ubuntu.com',
    'hide-top-bar@mathieu.bidon.ca',
}
try:
    raw=subprocess.check_output(['gsettings','get','org.gnome.shell','enabled-extensions'], text=True).strip()
    items=ast.literal_eval(raw)
    items=[x for x in items if x not in stale]
    for x in keep:
        if x not in items:
            items.append(x)
    subprocess.run(['gsettings','set','org.gnome.shell','enabled-extensions',str(items)], check=False)
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
}

install_appmenu(){
  local app_dir="$SOURCE_DIR/AppMenu"
  if [[ -d "$app_dir/.git" ]]; then
    git -C "$app_dir" fetch --depth=1 origin >/dev/null 2>&1 || true
    git -C "$app_dir" reset --hard origin/HEAD >/dev/null 2>&1 || true
  else
    git clone --depth=1 https://github.com/ChathurangaBW/AppMenu.git "$app_dir"
  fi
  bash "$app_dir/install.sh" --clean-stale
  local schema="$HOME/.local/share/gnome-shell/extensions/appmenu@ChathurangaBW.github.io/schemas"
  set_schema "$schema" org.gnome.shell.extensions.appmenu show-os-icon true
  set_schema "$schema" org.gnome.shell.extensions.appmenu use-real-menus true
  set_schema "$schema" org.gnome.shell.extensions.appmenu prefer-macos-style true
  set_schema "$schema" org.gnome.shell.extensions.appmenu show-user-switcher true
  set_schema "$schema" org.gnome.shell.extensions.appmenu show-workspace-indicator false
  set_schema "$schema" org.gnome.shell.extensions.appmenu hide-overview-button true
}

configure_theme(){
  install_ego 'user-theme@gnome-shell-extensions.gcampax.github.com' 50 || warn 'User Themes install failed.'
  gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-Light' 2>/dev/null || gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-light' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme 'MacTahoe' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme 'MacTahoe-cursors' 2>/dev/null || true
  local schema="$HOME/.local/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com/schemas"
  set_schema "$schema" org.gnome.shell.extensions.user-theme name 'MacTahoe-Light'
}

configure_window_controls(){
  # Force macOS traffic-light controls into the actual GTK window titlebar,
  # not into the GNOME panel. GTK uses this layout for client-side decorations.
  gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface gtk-decoration-layout 'close,minimize,maximize:' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface gtk-titlebar-double-click 'toggle-maximize' 2>/dev/null || true
}

patch_shell_theme(){
  local light="$HOME/.themes/MacTahoe-Light/gnome-shell/gnome-shell.css"
  local dark="$HOME/.themes/MacTahoe-Dark/gnome-shell/gnome-shell.css"
  local marker='/* MacOSify 1.7 Tahoe panel/window match */'
  local light_css="$marker\n#panel { background-color: #ffffff !important; color: #575757 !important; }\n#panel .panel-corner { -panel-corner-background-color: #ffffff !important; }\n#panel .panel-button { color: #575757 !important; }\n#panel .panel-button:hover, #panel .panel-button:active, #panel .panel-button:checked { color: #222222 !important; }\n"
  local dark_css="$marker\n#panel { background-color: #1c1c1e !important; color: #f5f5f7 !important; }\n#panel .panel-corner { -panel-corner-background-color: #1c1c1e !important; }\n#panel .panel-button { color: #f5f5f7 !important; }\n"
  for pair in "$light|$light_css" "$dark|$dark_css"; do
    local file="${pair%%|*}" css="${pair#*|}"
    [[ -f "$file" ]] || continue
    grep -Fq "$marker" "$file" || printf '\n%s' "$css" >> "$file"
  done
  # Keep GTK headerbars on the same opaque light/dark surface as the shell panel.
  for file in "$HOME/.themes/MacTahoe-Light/gtk-3.0/gtk.css" "$HOME/.themes/MacTahoe-Light/gtk-4.0/gtk.css"; do
    [[ -f "$file" ]] || continue
    grep -Fq 'MacOSify 1.7 headerbar match' "$file" || cat >> "$file" <<'CSS'

/* MacOSify 1.7 headerbar match */
headerbar, .titlebar { background-color: #ffffff !important; }
headerbar:backdrop, .titlebar:backdrop { background-color: #f2f2f2 !important; }
CSS
  done
}

configure_topbar(){
  install_ego 'hidetopbar@mathieu.bidon.ca' 50 || warn 'Hide Top Bar install failed.'
  local schema="$HOME/.local/share/gnome-shell/extensions/hidetopbar@mathieu.bidon.ca/schemas"
  set_schema "$schema" org.gnome.shell.extensions.hidetopbar enable-intellihide true
  set_schema "$schema" org.gnome.shell.extensions.hidetopbar mouse-sensitive true
  set_schema "$schema" org.gnome.shell.extensions.hidetopbar animation-time-autohide 0.20
  set_schema "$schema" org.gnome.shell.extensions.hidetopbar mouse-sensitive-fullscreen-window true
}

configure_dash2dock(){
  local schema="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
  [[ -d "$schema" ]] || { warn 'Dash2Dock schema directory missing.'; return; }
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite apps-icon true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite apps-icon-front true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite trash-icon true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite autohide-dash true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite autohide-dodge true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite icon-size 48
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite dock-location 0
}

configure_control_center(){
  install_ego 'kiwi@kemma' 50 || warn 'Kiwi install failed.'
}

configure_firefox(){
  local src="$SOURCE_DIR/MacTahoe-gtk-theme/other/firefox"
  [[ -d "$src/MacTahoe" ]] || { warn 'MacTahoe Firefox assets not found.'; return; }
  local bases=()
  [[ -d "$HOME/snap/firefox/common/.mozilla/firefox" ]] && bases+=("$HOME/snap/firefox/common/.mozilla/firefox")
  [[ -d "$HOME/.mozilla/firefox" ]] && bases+=("$HOME/.mozilla/firefox")
  [[ -d "$HOME/.config/mozilla/firefox" ]] && bases+=("$HOME/.config/mozilla/firefox")
  [[ -d "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" ]] && bases+=("$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox")
  ((${#bases[@]})) || { warn 'Firefox profile directory not initialized yet; theme will apply on the next MacOSify run.'; return; }

  local base target profile
  for base in "${bases[@]}"; do
    target="$base/firefox-themes"
    mkdir -p "$target"
    rm -rf "$target/MacTahoe"
    cp -a "$src/MacTahoe" "$target/MacTahoe"
    cp -f "$src/customChrome.css" "$target/customChrome.css"
    cp -f "$src/userChrome.css" "$target/userChrome.css"
    cp -f "$src/userContent.css" "$target/userContent.css"
    shopt -s nullglob
    local profiles=("$base"/*default*)
    shopt -u nullglob
    for profile in "${profiles[@]}"; do
      [[ -d "$profile" ]] || continue
      rm -rf "$profile/chrome"
      ln -sfn "$target" "$profile/chrome"
      local userjs="$profile/user.js"
      touch "$userjs"
      grep -Fq 'toolkit.legacyUserProfileCustomizations.stylesheets' "$userjs" || echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$userjs"
      grep -Fq 'browser.tabs.drawInTitlebar' "$userjs" || echo 'user_pref("browser.tabs.drawInTitlebar", true);' >> "$userjs"
      grep -Fq 'browser.uidensity' "$userjs" || echo 'user_pref("browser.uidensity", 0);' >> "$userjs"
      grep -Fq 'layers.acceleration.force-enabled' "$userjs" || echo 'user_pref("layers.acceleration.force-enabled", true);' >> "$userjs"
      grep -Fq 'widget.gtk.rounded-bottom-corners.enabled' "$userjs" || echo 'user_pref("widget.gtk.rounded-bottom-corners.enabled", true);' >> "$userjs"
      grep -Fq 'svg.context-properties.content.enabled' "$userjs" || echo 'user_pref("svg.context-properties.content.enabled", true);' >> "$userjs"
    done
    info "Firefox MacTahoe theme connected: $base"
  done
}

configure_machine(){
  local mem_mb cores cpu gpu profile session desktop
  . /etc/os-release 2>/dev/null || true
  mem_mb="$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)"
  cores="$(nproc 2>/dev/null || echo 1)"
  cpu="$(lscpu 2>/dev/null | awk -F: '/Model name/{gsub(/^ +| +$/,"",$2); print $2; exit}')"
  gpu="$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | head -1 | sed 's/^[^:]*: //')"
  session="${XDG_SESSION_TYPE:-wayland}"
  desktop="${XDG_CURRENT_DESKTOP:-GNOME}"
  if [[ "${MACOSIFY_PERFORMANCE:-auto}" != auto ]]; then profile="$MACOSIFY_PERFORMANCE"
  elif (( mem_mb < 4096 || cores <= 2 )); then profile="lite"
  elif (( mem_mb < 8192 )); then profile="balanced"
  else profile="high"; fi
  case "$profile" in
    lite) gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true ;;
    balanced|high) gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true ;;
    *) profile="balanced" ;;
  esac
  cat > "$STATE_DIR/machine-profile.conf" <<EOF
MACOSIFY_VERSION=$MACOSIFY_VERSION
OS=${PRETTY_NAME:-unknown}
KERNEL=$(uname -r)
ARCH=$(uname -m)
CPU=${cpu:-unknown}
CPU_CORES=$cores
RAM_MB=$mem_mb
GPU=${gpu:-unknown}
SESSION=$session
DESKTOP=$desktop
PERFORMANCE_PROFILE=$profile
EOF
  info "Machine profile: $profile | RAM ${mem_mb}MB | CPU ${cores} cores | GPU ${gpu:-unknown}"
}

verify(){
  info 'Running final Tahoe compatibility verification'
  local failures=0 enabled ds
  for dir in \
    "$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com" \
    "$HOME/.local/share/gnome-shell/extensions/appmenu@ChathurangaBW.github.io" \
    "$HOME/.local/share/gnome-shell/extensions/hidetopbar@mathieu.bidon.ca" \
    "$HOME/.local/share/gnome-shell/extensions/kiwi@kemma"; do
    [[ -f "$dir/metadata.json" ]] || { warn "Missing extension: $dir"; failures=$((failures+1)); }
  done
  enabled="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)"
  for id in appmenu@ChathurangaBW.github.io kiwi@kemma user-theme@gnome-shell-extensions.gcampax.github.com hidetopbar@mathieu.bidon.ca dash2dock-lite@icedman.github.com; do
    grep -q "$id" <<<"$enabled" || { warn "$id not persisted"; failures=$((failures+1)); }
  done
  grep -q 'ubuntu-dock@ubuntu.com' <<<"$enabled" && { warn 'Ubuntu Dock persisted'; failures=$((failures+1)); }
  [[ "$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null)" == "'close,minimize,maximize:'" ]] || { warn 'Window button layout incorrect'; failures=$((failures+1)); }
  [[ "$(gsettings get org.gnome.desktop.interface gtk-decoration-layout 2>/dev/null)" == "'close,minimize,maximize:'" ]] || { warn 'GTK decoration layout incorrect'; failures=$((failures+1)); }
  [[ "$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)" == *MacTahoe* ]] || { warn 'MacTahoe GTK theme not active'; failures=$((failures+1)); }
  [[ -f "$HOME/.themes/MacTahoe-Light/gnome-shell/gnome-shell.css" ]] || { warn 'MacTahoe shell theme missing'; failures=$((failures+1)); }
  ds="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
  [[ "$(GSETTINGS_SCHEMA_DIR="$ds" gsettings get org.gnome.shell.extensions.dash2dock-lite apps-icon-front 2>/dev/null)" == true ]] || { warn 'Launcher-first failed'; failures=$((failures+1)); }
  [[ "$(GSETTINGS_SCHEMA_DIR="$ds" gsettings get org.gnome.shell.extensions.dash2dock-lite trash-icon 2>/dev/null)" == true ]] || { warn 'Trash setting failed'; failures=$((failures+1)); }
  if [[ -d "$HOME/snap/firefox/common/.mozilla/firefox" ]]; then
    [[ -f "$HOME/snap/firefox/common/.mozilla/firefox/firefox-themes/userChrome.css" ]] || warn 'Firefox theme assets pending/not installed.'
  fi
  (( failures == 0 )) || { warn "Verification found $failures issue(s)."; return 1; }
  info 'Final Tahoe compatibility verification passed.'
}

main(){
  info "$PROJECT enhancement $MACOSIFY_VERSION — complete GNOME 50 Tahoe polish"
  persist_extensions
  install_appmenu || warn 'AppMenu stage failed.'
  configure_control_center
  configure_theme
  configure_window_controls
  configure_topbar
  configure_dash2dock
  configure_firefox
  patch_shell_theme
  configure_machine
  gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null || true
  persist_extensions
  verify || warn 'Some checks require a fresh GNOME session; persisted configuration remains written.'
  info '=== MACHINE CONFIGURATION ==='
  [[ -f "$STATE_DIR/machine-profile.conf" ]] && cat "$STATE_DIR/machine-profile.conf"
  info '=== END MACHINE CONFIGURATION ==='
  info 'Enhancement complete. Reboot/logout-login once to activate shell/theme changes.'
}

main "$@"
