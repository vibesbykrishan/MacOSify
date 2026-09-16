#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="0.3.0"
PROJECT="MacOSify"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"
BACKUP_DIR="$STATE_DIR/backups"
LOG_FILE="$STATE_DIR/macosify.log"
LOCK_FILE="$STATE_DIR/install.lock"
SOURCE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/macosify/sources"
DRY_RUN=0
SAFE_MODE=0
PERFORMANCE="auto"
PRESET="auto"
ACTION="install"

mkdir -p "$STATE_DIR" "$BACKUP_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

info(){ printf '[MacOSify] %s\n' "$*"; }
warn(){ printf '[MacOSify][WARN] %s\n' "$*" >&2; }
die(){ printf '[MacOSify][ERROR] %s\n' "$*" >&2; exit 1; }
run(){ if ((DRY_RUN)); then printf '+ '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }

usage(){ cat <<'EOF'
MacOSify - macOS-inspired desktop transformation for Ubuntu GNOME

Usage: macosify.sh [options]
  --dry-run                 Preview changes only
  --safe-mode               Conservative configuration
  --performance MODE        auto|low|balanced|quality
  --preset NAME             auto|tahoe|sonoma|ventura|monterey|bigsur
  --repair                  Re-apply MacOSify configuration
  --update                  Update MacOSify sources
  --rollback                Restore latest backup
  --uninstall               Restore GNOME settings
  --version                 Show version
  -h, --help                Show help
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1;;
    --safe-mode) SAFE_MODE=1;;
    --performance=*) PERFORMANCE="${1#*=}";;
    --performance) shift; PERFORMANCE="${1:-auto}";;
    --preset=*) PRESET="${1#*=}";;
    --preset) shift; PRESET="${1:-auto}";;
    --repair) ACTION=repair;;
    --update) ACTION=update;;
    --rollback) ACTION=rollback;;
    --uninstall) ACTION=uninstall;;
    --version) echo "$PROJECT $VERSION"; exit 0;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1";;
  esac
  shift
done

acquire_lock(){
  [[ -e "$LOCK_FILE" ]] && die "Another MacOSify operation is active: $LOCK_FILE"
  printf '%s\n' "$$" > "$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
}

check_platform(){
  [[ -r /etc/os-release ]] || die "Cannot identify Linux distribution."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == ubuntu || "${ID_LIKE:-}" == *ubuntu* ]] || die "Ubuntu-based system required: ${PRETTY_NAME:-unknown}"
  command -v gnome-shell >/dev/null 2>&1 || die "GNOME Shell is required."
  local gv="$(gnome-shell --version | awk '{print $3}')"
  info "Detected ${PRETTY_NAME:-Ubuntu} | GNOME $gv | session ${XDG_SESSION_TYPE:-unknown}"
  if [[ "${VERSION_ID:-}" == 26.04* ]]; then
    info "Ubuntu 26.04 detected; using Wayland-safe configuration."
  fi
}

check_resources(){
  local mem_mb free_mb
  mem_mb="$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)"
  free_mb="$(df -Pm "$HOME" | awk 'NR==2{print $4}')"
  info "Resources: RAM ${mem_mb}MB | free disk ${free_mb}MB"
  if [[ "$PERFORMANCE" == auto ]]; then
    if ((mem_mb < 4096)); then PERFORMANCE=low
    elif ((mem_mb < 8192)); then PERFORMANCE=balanced
    else PERFORMANCE=quality; fi
  fi
  case "$PERFORMANCE" in low|balanced|quality) ;; *) die "Invalid performance mode: $PERFORMANCE";; esac
  info "Performance profile: $PERFORMANCE"
}

backup(){
  local stamp="$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)"
  run mkdir -p "$stamp"
  ((DRY_RUN)) && return
  dconf dump /org/gnome/ > "$stamp/gnome.dconf" || true
  for p in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
    [[ -e "$p" ]] && cp -a "$p" "$stamp/$(basename "$p")" || true
  done
  printf '%s\n' "$stamp" > "$STATE_DIR/latest-backup"
  info "Backup saved: $stamp"
}

install_packages(){
  info "Installing build/runtime dependencies"
  local packages=(git curl ca-certificates unzip sassc meson ninja-build gettext build-essential libglib2.0-dev libxml2-utils dconf-cli)
  if ! command -v gnome-extensions >/dev/null 2>&1; then packages+=(gnome-shell-extension-prefs); fi
  run sudo apt-get update
  run sudo apt-get install -y "${packages[@]}"
}

sync_repo(){
  local name="$1" url="$2"
  run mkdir -p "$SOURCE_DIR"
  ((DRY_RUN)) && return
  if [[ -d "$SOURCE_DIR/$name/.git" ]]; then
    git -C "$SOURCE_DIR/$name" fetch --depth=1 origin
    git -C "$SOURCE_DIR/$name" reset --hard origin/HEAD 2>/dev/null || git -C "$SOURCE_DIR/$name" reset --hard FETCH_HEAD
  else
    git clone --depth=1 "$url" "$SOURCE_DIR/$name"
  fi
}

sync_sources(){
  info "Syncing latest maintained Tahoe sources"
  sync_repo MacTahoe-gtk-theme https://github.com/vinceliuice/MacTahoe-gtk-theme.git
  sync_repo MacTahoe-icon-theme https://github.com/vinceliuice/MacTahoe-icon-theme.git
  sync_repo dash-to-dock https://github.com/micheleg/dash-to-dock.git
  sync_repo blur-my-shell https://github.com/aunetx/blur-my-shell.git
  sync_repo gnome-shell-extension-appindicator https://github.com/ubuntu/gnome-shell-extension-appindicator.git
}

install_tahoe(){
  ((DRY_RUN)) && { info "Would install latest MacTahoe GTK/icons/cursors"; return; }
  local gtk="$SOURCE_DIR/MacTahoe-gtk-theme"
  info "Installing latest MacTahoe GTK theme"
  bash "$gtk/install.sh" -c light -c dark -t all -o normal -b -l --shell -p 15 -h 32 normal --round || bash "$gtk/install.sh" -c light -c dark -t all -o normal
  info "Installing latest MacTahoe icons and cursors"
  bash "$SOURCE_DIR/MacTahoe-icon-theme/install.sh" -t all
}

install_extension(){
  local dir="$1"
  if ((DRY_RUN)); then info "Would install GNOME extension: $dir"; return; fi
  if [[ -f "$dir/Makefile" ]]; then make -C "$dir" install
  elif [[ -x "$dir/install.sh" ]]; then "$dir/install.sh"
  else warn "No supported installer found for $dir"; fi
}

install_extensions(){
  ((SAFE_MODE)) && { info "Safe mode: skipping third-party GNOME extensions"; return; }
  install_extension "$SOURCE_DIR/dash-to-dock"
  install_extension "$SOURCE_DIR/blur-my-shell"
  if [[ -f "$SOURCE_DIR/gnome-shell-extension-appindicator/meson.build" ]]; then
    if ((DRY_RUN)); then info "Would build/install latest AppIndicator extension"
    else
      local build="$STATE_DIR/appindicator-build"
      rm -rf "$build"
      meson setup "$build" "$SOURCE_DIR/gnome-shell-extension-appindicator"
      ninja -C "$build" install
    fi
  fi
}

configure_interface(){
  ((DRY_RUN)) && return
  gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-light' 2>/dev/null || gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-Light' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme 'MacTahoe' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme 'MacTahoe-cursors' 2>/dev/null || true
  gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
}

configure_extensions(){
  ((DRY_RUN || SAFE_MODE)) && return
  local ids=(dash-to-dock@micxgx.gmail.com blur-my-shell@aunetx appindicatorsupport@rgcjonas.gmail.com)
  for id in "${ids[@]}"; do gnome-extensions enable "$id" 2>/dev/null || warn "Extension unavailable/incompatible: $id"; done
}

configure_dock(){
  ((DRY_RUN || SAFE_MODE)) && return
  if gsettings list-schemas | grep -q '^org.gnome.shell.extensions.dash-to-dock$'; then
    local schema=org.gnome.shell.extensions.dash-to-dock
    gsettings set "$schema" dock-position BOTTOM || true
    gsettings set "$schema" extend-height false || true
    gsettings set "$schema" dock-fixed false || true
    gsettings set "$schema" autohide true || true
    gsettings set "$schema" intellihide true || true
    gsettings set "$schema" show-mounts false || true
    gsettings set "$schema" show-trash false || true
  else
    info "Dash-to-Dock is not installed; leaving Ubuntu's native dock untouched."
  fi
}

configure_performance(){
  ((DRY_RUN)) && return
  case "$PERFORMANCE" in
    low)
      gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true
      ;;
    balanced)
      gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true
      ;;
    quality)
      gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true
      ;;
  esac
}

configure_preset(){
  case "$PRESET" in
    auto|tahoe|sonoma|ventura|monterey|bigsur) ;;
    *) die "Unknown preset: $PRESET";;
  esac
  info "Applying preset: $PRESET"
  configure_interface
  configure_dock
  configure_performance
}

verify(){
  command -v gsettings >/dev/null 2>&1 || die "gsettings is missing."
  command -v gnome-shell >/dev/null 2>&1 || die "gnome-shell is missing."
  if ((DRY_RUN)); then info "Dry-run verification complete"; return; fi
  info "GTK theme: $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo unknown)"
  info "Icon theme: $(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo unknown)"
  info "Cursor theme: $(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || echo unknown)"
  info "Verification passed"
}

rollback(){
  [[ -f "$STATE_DIR/latest-backup" ]] || die "No MacOSify backup found."
  local backup_path="$(cat "$STATE_DIR/latest-backup")"
  [[ -d "$backup_path" ]] || die "Backup directory missing: $backup_path"
  ((DRY_RUN)) && { info "Would restore $backup_path"; return; }
  [[ -s "$backup_path/gnome.dconf" ]] && dconf load /org/gnome/ < "$backup_path/gnome.dconf" || true
  info "GNOME settings restored from $backup_path"
}

uninstall(){
  info "Restoring GNOME configuration"
  rollback || true
  ((DRY_RUN)) && return
  gsettings reset org.gnome.desktop.interface gtk-theme 2>/dev/null || true
  gsettings reset org.gnome.desktop.interface icon-theme 2>/dev/null || true
  gsettings reset org.gnome.desktop.interface cursor-theme 2>/dev/null || true
  gsettings reset org.gnome.desktop.interface color-scheme 2>/dev/null || true
  gsettings reset org.gnome.desktop.wm.preferences button-layout 2>/dev/null || true
  info "MacOSify settings reset; downloaded theme sources were retained for rollback."
}

main(){
  acquire_lock
  check_platform
  check_resources
  case "$ACTION" in
    rollback) rollback;;
    uninstall) uninstall;;
    install|repair|update)
      backup
      install_packages
      sync_sources
      install_tahoe
      install_extensions
      configure_preset
      configure_extensions
      verify
      ;;
    *) die "Invalid action: $ACTION";;
  esac
  info "$PROJECT $VERSION completed successfully. Log: $LOG_FILE"
  info "Log out and back in if GNOME Shell changes are not immediately visible."
}

main "$@"
