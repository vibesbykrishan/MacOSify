#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT="MacOSify"
VERSION="1.6.0"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"
SOURCE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/macosify/sources"
mkdir -p "$STATE_DIR" "$SOURCE_DIR"

info(){ printf '[MacOSify] %s\n' "$*"; }
warn(){ printf '[MacOSify][WARN] %s\n' "$*" >&2; }

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
    if u not in xs:
        xs.append(u)
        subprocess.run(['gsettings','set','org.gnome.shell','enabled-extensions',str(xs)], check=False)
except Exception:
    pass
PY
}

set_schema(){
  local dir="$1" schema="$2" key="$3" value="$4"
  [[ -d "$dir" ]] || return 0
  GSETTINGS_SCHEMA_DIR="$dir" gsettings set "$schema" "$key" "$value" 2>/dev/null || true
}

install_ego(){
  local uuid="$1"
  local shell="${2:-50}"
  local zip="$STATE_DIR/${uuid}.zip"
  local url
  url="$(curl -fsSL --retry 3 --connect-timeout 15 "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("download_url",""))')" || return 1
  [[ -n "$url" ]] || return 1
  curl -fL --retry 3 --connect-timeout 15 -o "$zip" "https://extensions.gnome.org${url}"
  gnome-extensions install --force "$zip" >/dev/null
  rm -f "$zip"
  gnome-extensions enable "$uuid" 2>/dev/null || true
  persist "$uuid"
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
  persist 'appmenu@ChathurangaBW.github.io'
  local schema="$app_dir/schemas"
  set_schema "$schema" org.gnome.shell.extensions.appmenu show-os-icon true
  set_schema "$schema" org.gnome.shell.extensions.appmenu use-real-menus true
  set_schema "$schema" org.gnome.shell.extensions.appmenu prefer-macos-style true
  set_schema "$schema" org.gnome.shell.extensions.appmenu show-user-switcher true
  set_schema "$schema" org.gnome.shell.extensions.appmenu show-workspace-indicator false
  set_schema "$schema" org.gnome.shell.extensions.appmenu hide-overview-button true
}

configure_theme(){
  install_ego 'user-theme@gnome-shell-extensions.gcampax.github.com' 50 || warn 'User Themes could not be installed.'
  gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-Light' 2>/dev/null || gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-light' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme 'MacTahoe' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme 'MacTahoe-cursors' 2>/dev/null || true
  local schema="$HOME/.local/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com/schemas"
  set_schema "$schema" org.gnome.shell.extensions.user-theme name 'MacTahoe-Light'
}

configure_topbar(){
  if install_ego 'hidetopbar@mathieu.bidon.ca' 50; then
    local schema="$HOME/.local/share/gnome-shell/extensions/hidetopbar@mathieu.bidon.ca/schemas"
    set_schema "$schema" org.gnome.shell.extensions.hidetopbar enable-intellihide true
    set_schema "$schema" org.gnome.shell.extensions.hidetopbar mouse-sensitive true
    set_schema "$schema" org.gnome.shell.extensions.hidetopbar animation-time-autohide 0.20
  else
    warn 'Hide Top Bar could not be installed.'
  fi
}

configure_dash2dock(){
  local schema="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
  [[ -d "$schema" ]] || { warn 'Dash2Dock schema directory not found.'; return; }
  persist 'dash2dock-lite@icedman.github.com'
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite apps-icon true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite apps-icon-front true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite trash-icon true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite autohide-dash true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite autohide-dodge true
  set_schema "$schema" org.gnome.shell.extensions.dash2dock-lite icon-size 48
}

configure_control_center(){
  install_ego 'kiwi@kemma' 50 || warn 'Kiwi quick-settings enhancement could not be installed.'
}

configure_machine(){
  local mem_mb cores cpu gpu profile session desktop
  mem_mb="$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)"
  cores="$(nproc 2>/dev/null || echo 1)"
  cpu="$(lscpu 2>/dev/null | awk -F: '/Model name/{gsub(/^ +| +$/,"",$2); print $2; exit}')"
  gpu="$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | head -1 | sed 's/^[^:]*: //')"
  session="${XDG_SESSION_TYPE:-wayland}"
  desktop="${XDG_CURRENT_DESKTOP:-GNOME}"

  if [[ "${MACOSIFY_PERFORMANCE:-auto}" != auto ]]; then
    profile="$MACOSIFY_PERFORMANCE"
  elif (( mem_mb < 4096 || cores <= 2 )); then
    profile="lite"
  elif (( mem_mb < 8192 )); then
    profile="balanced"
  else
    profile="high"
  fi

  case "$profile" in
    lite) gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true ;;
    balanced|high) gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true ;;
    *) profile="balanced" ;;
  esac

  cat > "$STATE_DIR/machine-profile.conf" <<EOF
MACOSIFY_VERSION=$VERSION
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
  info "Machine profile saved: $STATE_DIR/machine-profile.conf"
}

verify(){
  info 'Running final compatibility verification'
  local failures=0
  local d2d="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com"
  [[ -f "$d2d/metadata.json" ]] || { warn 'Dash2Dock Animated files missing'; failures=$((failures+1)); }
  [[ -f "$HOME/.local/share/gnome-shell/extensions/appmenu@ChathurangaBW.github.io/metadata.json" ]] || { warn 'AppMenu files missing'; failures=$((failures+1)); }
  [[ -f "$HOME/.local/share/gnome-shell/extensions/hidetopbar@mathieu.bidon.ca/metadata.json" ]] || { warn 'Hide Top Bar files missing'; failures=$((failures+1)); }
  [[ -f "$HOME/.local/share/gnome-shell/extensions/kiwi@kemma/metadata.json" ]] || { warn 'Kiwi files missing'; failures=$((failures+1)); }

  local enabled
  enabled="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)"
  for id in appmenu@ChathurangaBW.github.io kiwi@kemma user-theme@gnome-shell-extensions.gcampax.github.com hidetopbar@mathieu.bidon.ca dash2dock-lite@icedman.github.com; do
    if grep -q "$id" <<<"$enabled"; then info "$id: persisted"; else warn "$id: not persisted"; failures=$((failures+1)); fi
  done
  grep -q "ubuntu-dock@ubuntu.com" <<<"$enabled" && { warn 'Ubuntu Dock still persisted'; failures=$((failures+1)); } || info 'Ubuntu Dock: disabled/persisted'

  info "GTK: $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo unknown)"
  info "Color scheme: $(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo unknown)"
  info "Icons: $(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo unknown)"

  local ds="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
  if [[ -d "$ds" ]]; then
    [[ "$(GSETTINGS_SCHEMA_DIR="$ds" gsettings get org.gnome.shell.extensions.dash2dock-lite apps-icon-front 2>/dev/null)" == true ]] || { warn 'Dash2Dock launcher-first setting failed'; failures=$((failures+1)); }
    [[ "$(GSETTINGS_SCHEMA_DIR="$ds" gsettings get org.gnome.shell.extensions.dash2dock-lite trash-icon 2>/dev/null)" == true ]] || { warn 'Dash2Dock trash setting failed'; failures=$((failures+1)); }
    [[ "$(GSETTINGS_SCHEMA_DIR="$ds" gsettings get org.gnome.shell.extensions.dash2dock-lite autohide-dash 2>/dev/null)" == true ]] || { warn 'Dash2Dock auto-hide setting failed'; failures=$((failures+1)); }
  fi

  (( failures == 0 )) || { warn "Final verification found $failures issue(s)."; return 1; }
  info 'Final compatibility verification passed.'
}

main(){
  info "$PROJECT enhancement $VERSION — GNOME 50/Tahoe compatibility layer"
  info 'Ubuntu 26.04 ships GNOME 50; MacOSify targets the GNOME 50 extension APIs.'
  configure_machine
  install_appmenu || warn 'AppMenu stage failed.'
  configure_control_center
  configure_theme
  configure_topbar
  configure_dash2dock
  gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null || true
  if ! verify; then
    warn 'Some extension checks need a fresh GNOME session; persisted configuration was still written.'
  fi
  info '=== MACHINE CONFIGURATION ==='
  [[ -f "$STATE_DIR/machine-profile.conf" ]] && cat "$STATE_DIR/machine-profile.conf"
  info '=== END MACHINE CONFIGURATION ==='
  info 'Enhancement stage complete. Log out/in or reboot once to activate newly installed GNOME Shell extensions.'
}

main "$@"
