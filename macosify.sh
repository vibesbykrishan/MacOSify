#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.0.0"
PROJECT="MacOSify"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"
SOURCE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/macosify/sources"
BACKUP_DIR="$STATE_DIR/backups"
LOG_FILE="$STATE_DIR/macosify.log"
LOCK_FILE="$STATE_DIR/install.lock"
ASSET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/macosify/assets"
DRY_RUN=0
SAFE_MODE=0
ACTION="install"
PERFORMANCE="auto"

mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$SOURCE_DIR" "$ASSET_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

info(){ printf '[MacOSify] %s\n' "$*"; }
warn(){ printf '[MacOSify][WARN] %s\n' "$*" >&2; }
die(){ printf '[MacOSify][ERROR] %s\n' "$*" >&2; exit 1; }

usage(){ cat <<'USAGE'
MacOSify 1.0 - Ubuntu GNOME -> macOS Tahoe inspired desktop

Usage: macosify.sh [options]
  --dry-run             Preview changes only
  --safe-mode           Conservative mode
  --performance MODE    auto|lite|balanced|high
  --repair              Repair MacOSify configuration
  --update              Refresh sources and re-apply
  --rollback            Restore latest backup
  --uninstall           Restore the pre-MacOSify state
  --doctor              Diagnose the installation
  --version             Show version
  -h, --help            Show help
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1;;
    --safe-mode) SAFE_MODE=1;;
    --performance=*) PERFORMANCE="${1#*=}";;
    --performance) shift; PERFORMANCE="${1:-auto}";;
    --repair) ACTION=repair;;
    --update) ACTION=update;;
    --rollback) ACTION=rollback;;
    --uninstall) ACTION=uninstall;;
    --doctor) ACTION=doctor;;
    --version) echo "$PROJECT $VERSION"; exit 0;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1";;
  esac
  shift
done

acquire_lock(){
  [[ -e "$LOCK_FILE" ]] && die "Another MacOSify operation is active."
  printf '%s\n' "$$" > "$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
}

check_platform(){
  [[ -r /etc/os-release ]] || die "Cannot identify Linux distribution."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == ubuntu || "${ID_LIKE:-}" == *ubuntu* ]] || die "Ubuntu-based system required: ${PRETTY_NAME:-unknown}"
  command -v gnome-shell >/dev/null || die "GNOME Shell is required."
  local gv="$(gnome-shell --version | awk '{print $3}')"
  info "Detected ${PRETTY_NAME:-Ubuntu} | GNOME $gv | session ${XDG_SESSION_TYPE:-unknown}"
  [[ "${VERSION_ID:-}" == 26.04* ]] && info "Ubuntu 26.04 detected; GNOME 50/Wayland-safe profile enabled."
}

check_resources(){
  local mem_mb
  mem_mb="$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)"
  if [[ "$PERFORMANCE" == auto ]]; then
    if ((mem_mb < 4096)); then PERFORMANCE=lite
    elif ((mem_mb < 8192)); then PERFORMANCE=balanced
    else PERFORMANCE=high; fi
  fi
  case "$PERFORMANCE" in lite|balanced|high) ;; *) die "Invalid performance profile: $PERFORMANCE";; esac
  info "RAM ${mem_mb}MB | performance profile: $PERFORMANCE"
}

backup(){
  local stamp="$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$stamp"
  ((DRY_RUN)) && return
  dconf dump /org/gnome/ > "$stamp/user-gnome.dconf" || true
  [[ -f /etc/default/grub ]] && sudo cp -a /etc/default/grub "$stamp/grub" || true
  [[ -d /etc/dconf/db/gdm.d ]] && sudo cp -a /etc/dconf/db/gdm.d "$stamp/gdm.d" || true
  [[ -f /etc/dconf/profile/gdm ]] && sudo cp -a /etc/dconf/profile/gdm "$stamp/gdm-profile" || true
  [[ -d /etc/plymouth ]] && sudo cp -a /etc/plymouth "$stamp/plymouth" || true
  printf '%s\n' "$stamp" > "$STATE_DIR/latest-backup"
  info "Backup saved: $stamp"
}

install_deps(){
  local packages=(git curl ca-certificates wget unzip rsync imagemagick plymouth plymouth-themes dconf-cli gsettings-desktop-schemas gnome-shell-extension-prefs sassc meson ninja-build gettext build-essential libglib2.0-dev libxml2-utils)
  info "Checking/installing required dependencies"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

sync_repo(){
  local name="$1" url="$2"
  if [[ -d "$SOURCE_DIR/$name/.git" ]]; then
    git -C "$SOURCE_DIR/$name" fetch --depth=1 origin
    git -C "$SOURCE_DIR/$name" reset --hard origin/HEAD 2>/dev/null || git -C "$SOURCE_DIR/$name" reset --hard FETCH_HEAD
  else
    git clone --depth=1 "$url" "$SOURCE_DIR/$name"
  fi
}

sync_sources(){
  info "Fetching current Tahoe components"
  sync_repo MacTahoe-gtk-theme https://github.com/vinceliuice/MacTahoe-gtk-theme.git
  sync_repo MacTahoe-icon-theme https://github.com/vinceliuice/MacTahoe-icon-theme.git
  sync_repo dash-to-dock https://github.com/micheleg/dash-to-dock.git
  sync_repo blur-my-shell https://github.com/aunetx/blur-my-shell.git
  sync_repo gnome-shell-extension-appindicator https://github.com/ubuntu/gnome-shell-extension-appindicator.git
}

install_tahoe(){
  local gtk="$SOURCE_DIR/MacTahoe-gtk-theme"
  info "Installing MacTahoe GTK/Shell theme"
  if ! bash "$gtk/install.sh" -c light -c dark -t all -o normal -b -l --shell -p 15 -h 32 normal --round; then
    bash "$gtk/install.sh" -c light -c dark -t all -o normal
  fi
  info "Installing MacTahoe icons/cursors"
  bash "$SOURCE_DIR/MacTahoe-icon-theme/install.sh" -t all
}

install_dash2dock_animated(){
  local zip="$STATE_DIR/dash2dock-animated-v92.zip"
  local url="https://extensions.gnome.org/extension-data/dash2dock-liteicedman.v92.shell-extension.zip"
  info "Installing Dash2Dock Animated v92 (GNOME 50 compatible)"
  curl -fL --retry 3 --connect-timeout 15 -o "$zip" "$url"
  gnome-extensions install --force "$zip"
  rm -f "$zip"
}

install_blur(){
  ((SAFE_MODE)) && { info "Safe mode: skipping Blur My Shell"; return; }
  local dir="$SOURCE_DIR/blur-my-shell"
  [[ -f "$dir/Makefile" ]] && make -C "$dir" install || warn "Blur My Shell build failed; continuing without it."
}

install_appindicator(){
  ((SAFE_MODE)) && return
  local dir="$SOURCE_DIR/gnome-shell-extension-appindicator"
  [[ -f "$dir/meson.build" ]] || return
  local build="$STATE_DIR/appindicator-build"
  rm -rf "$build"
  meson setup "$build" "$dir" --prefix="$HOME/.local" >/dev/null
  ninja -C "$build" install
}

make_wallpaper(){
  local dark="$ASSET_DIR/MacOSify-Tahoe-Dark.jpeg"
  local light="$ASSET_DIR/MacOSify-Tahoe-Light.jpeg"
  [[ -f "$dark" ]] || curl -fL --retry 3 -o "$dark" "https://raw.githubusercontent.com/vinceliuice/MacTahoe-kde/main/wallpapers/MacTahoe-Dark/contents/images/3840x2160.jpeg"
  [[ -f "$light" ]] || curl -fL --retry 3 -o "$light" "https://raw.githubusercontent.com/vinceliuice/MacTahoe-kde/main/wallpapers/MacTahoe-Light/contents/images/3840x2160.jpeg"
  sudo install -Dm644 "$dark" /usr/share/backgrounds/macosify-tahoe-dark.jpeg
  sudo install -Dm644 "$light" /usr/share/backgrounds/macosify-tahoe-light.jpeg
}

make_logo(){
  local svg="$ASSET_DIR/macosify-logo.svg"
  cat > "$svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#ffffff"/><stop offset="1" stop-color="#b8c2d9"/></linearGradient></defs>
<rect width="512" height="512" rx="128" fill="#10131a"/>
<path d="M150 365V145h44l62 91 62-91h44v220h-47V218l-59 87-59-87v147z" fill="url(#g)"/>
</svg>
SVG
  if command -v magick >/dev/null; then magick "$svg" -background none -resize 512x512 "$ASSET_DIR/macosify-logo.png"; else convert "$svg" -background none -resize 512x512 "$ASSET_DIR/macosify-logo.png"; fi
  sudo install -Dm644 "$ASSET_DIR/macosify-logo.png" /usr/share/pixmaps/macosify-logo.png
}

install_plymouth(){
  info "Installing silent Tahoe-inspired Plymouth boot splash"
  local dir="$STATE_DIR/plymouth-theme"
  mkdir -p "$dir"
  cat > "$dir/macosify-tahoe.plymouth" <<'PLY'
[Plymouth Theme]
Name=MacOSify Tahoe
Description=MacOSify Tahoe-inspired silent splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/macosify-tahoe
ScriptFile=/usr/share/plymouth/themes/macosify-tahoe/macosify-tahoe.script
PLY
  cat > "$dir/macosify-tahoe.script" <<'SCRIPT'
logo = Image("macosify-logo.png");
sprite = Sprite(logo);
sprite.SetX((Window.GetWidth() - logo.GetWidth()) / 2);
sprite.SetY((Window.GetHeight() - logo.GetHeight()) / 2);
sprite.SetZ(10);
Window.SetBackgroundTopColor(0.035, 0.045, 0.065);
Window.SetBackgroundBottomColor(0.005, 0.008, 0.015);
SCRIPT
  sudo rm -rf /usr/share/plymouth/themes/macosify-tahoe
  sudo mkdir -p /usr/share/plymouth/themes/macosify-tahoe
  sudo cp "$dir/macosify-tahoe.plymouth" "$dir/macosify-tahoe.script" /usr/share/plymouth/themes/macosify-tahoe/
  sudo cp /usr/share/pixmaps/macosify-logo.png /usr/share/plymouth/themes/macosify-tahoe/macosify-logo.png
  sudo plymouth-set-default-theme -R macosify-tahoe
  sudo update-initramfs -u
}

configure_grub(){
  info "Configuring silent graphical boot"
  local f=/etc/default/grub
  sudo cp -a "$f" "$f.macosify-backup" 2>/dev/null || true
  sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' "$f" || true
  if grep -q '^GRUB_TIMEOUT=' "$f"; then sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$f"; else echo 'GRUB_TIMEOUT=0' | sudo tee -a "$f" >/dev/null; fi
  local current
  current="$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$f" | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/' || true)"
  for flag in quiet splash loglevel=3 systemd.show_status=false rd.systemd.show_status=false udev.log_priority=3; do
    [[ " $current " == *" $flag "* ]] || current="$current $flag"
  done
  sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$current\"|" "$f"
  sudo update-grub
}

configure_gdm(){
  info "Configuring Tahoe login/lock screen defaults"
  sudo mkdir -p /etc/dconf/profile /etc/dconf/db/gdm.d
  if [[ ! -f /etc/dconf/profile/gdm ]] || ! grep -q 'system-db:gdm' /etc/dconf/profile/gdm; then
    sudo tee /etc/dconf/profile/gdm >/dev/null <<'EOF2'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF2
  fi
  sudo tee /etc/dconf/db/gdm.d/00-macosify >/dev/null <<EOF2
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/macosify-tahoe-dark.jpeg'
picture-uri-dark='file:///usr/share/backgrounds/macosify-tahoe-dark.jpeg'
picture-options='zoom'
primary-color='#10131a'
secondary-color='#05070b'

[org/gnome/desktop/screensaver]
picture-uri='file:///usr/share/backgrounds/macosify-tahoe-dark.jpeg'

[org/gnome/login-screen]
banner-message-enable=false
logo='/usr/share/pixmaps/macosify-logo.png'
EOF2
  sudo dconf update
}

configure_user(){
  local light="$ASSET_DIR/MacOSify-Tahoe-Light.jpeg"
  local dark="$ASSET_DIR/MacOSify-Tahoe-Dark.jpeg"
  gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-light' 2>/dev/null || gsettings set org.gnome.desktop.interface gtk-theme 'MacTahoe-Light' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme 'MacTahoe' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme 'MacTahoe-cursors' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true
  gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
  gsettings set org.gnome.desktop.background picture-uri "file://$light" 2>/dev/null || true
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$dark" 2>/dev/null || true
  gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true
  gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null || true
  gnome-extensions disable desktop-icons@csoriano 2>/dev/null || true
  gnome-extensions disable ding@rastersoft.com 2>/dev/null || true
  gnome-extensions disable ubuntu-appindicators@ubuntu.com 2>/dev/null || true
}

configure_dash2dock(){
  local uuid='dash2dock-lite@icedman'
  gnome-extensions enable "$uuid" 2>/dev/null || gnome-extensions enable 'dash2dock-animated@icedman' 2>/dev/null || true
  if gsettings list-schemas | grep -q '^org.gnome.shell.extensions.dash2dock-lite$'; then
    local s=org.gnome.shell.extensions.dash2dock-lite
    gsettings set "$s" dock-position 'BOTTOM' 2>/dev/null || true
    gsettings set "$s" autohide true 2>/dev/null || true
    gsettings set "$s" intellihide true 2>/dev/null || true
    gsettings set "$s" icon-size 48 2>/dev/null || true
  fi
  if gsettings list-schemas | grep -q '^org.gnome.shell.extensions.dash-to-dock$'; then
    local s=org.gnome.shell.extensions.dash-to-dock
    gsettings set "$s" dock-position 'BOTTOM' 2>/dev/null || true
    gsettings set "$s" dock-fixed false 2>/dev/null || true
    gsettings set "$s" autohide true 2>/dev/null || true
    gsettings set "$s" intellihide true 2>/dev/null || true
    gsettings set "$s" animate-show-apps true 2>/dev/null || true
    gsettings set "$s" animation-time 0.22 2>/dev/null || true
    gsettings set "$s" show-mounts false 2>/dev/null || true
    gsettings set "$s" show-trash true 2>/dev/null || true
    gsettings set "$s" extend-height false 2>/dev/null || true
    gsettings set "$s" always-center-icons true 2>/dev/null || true
    gsettings set "$s" custom-theme-shrink true 2>/dev/null || true
    gsettings set "$s" background-opacity 0.72 2>/dev/null || true
  fi
}

configure_performance(){
  gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null || true
}

configure_extensions(){
  ((SAFE_MODE)) && return
  for id in blur-my-shell@aunetx appindicatorsupport@rgcjonas.gmail.com; do
    gnome-extensions enable "$id" 2>/dev/null || warn "Extension unavailable: $id"
  done
  configure_dash2dock
}

verify(){
  info "Running verification"
  local failures=0
  command -v gsettings >/dev/null || { warn 'gsettings missing'; failures=$((failures+1)); }
  command -v gnome-extensions >/dev/null || { warn 'gnome-extensions missing'; failures=$((failures+1)); }
  gnome-extensions info dash2dock-lite@icedman >/dev/null 2>&1 || warn 'Dash2Dock Animated may require logout/login before metadata is visible.'
  [[ -f /usr/share/plymouth/themes/macosify-tahoe/macosify-tahoe.plymouth ]] || { warn 'Plymouth theme missing'; failures=$((failures+1)); }
  [[ -f /usr/share/backgrounds/macosify-tahoe-dark.jpeg ]] || { warn 'Wallpaper missing'; failures=$((failures+1)); }
  info "GTK: $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo unknown)"
  info "Icons: $(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo unknown)"
  info "Cursor: $(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || echo unknown)"
  ((failures==0)) || die "Verification found $failures critical issue(s). See $LOG_FILE"
  info "Verification passed."
}

rollback(){
  [[ -f "$STATE_DIR/latest-backup" ]] || die 'No MacOSify backup found.'
  local b; b="$(cat "$STATE_DIR/latest-backup")"
  [[ -d "$b" ]] || die "Backup missing: $b"
  dconf load /org/gnome/ < "$b/user-gnome.dconf" 2>/dev/null || true
  [[ -f "$b/grub" ]] && sudo cp -a "$b/grub" /etc/default/grub && sudo update-grub || true
  [[ -d "$b/gdm.d" ]] && sudo rm -rf /etc/dconf/db/gdm.d && sudo cp -a "$b/gdm.d" /etc/dconf/db/gdm.d || true
  [[ -f "$b/gdm-profile" ]] && sudo cp -a "$b/gdm-profile" /etc/dconf/profile/gdm || true
  sudo dconf update || true
  info "Rollback complete."
}

uninstall(){
  rollback
  gnome-extensions disable dash2dock-lite@icedman 2>/dev/null || true
  gnome-extensions disable blur-my-shell@aunetx 2>/dev/null || true
  gnome-extensions disable appindicatorsupport@rgcjonas.gmail.com 2>/dev/null || true
  gnome-extensions enable ubuntu-dock@ubuntu.com 2>/dev/null || true
  sudo plymouth-set-default-theme -R ubuntu-text 2>/dev/null || sudo plymouth-set-default-theme -R ubuntu-logo 2>/dev/null || true
  info 'MacOSify configuration removed/restored. Reboot recommended.'
}

doctor(){
  info "MacOSify Doctor $VERSION"
  . /etc/os-release
  echo "OS: ${PRETTY_NAME:-unknown}"
  echo "GNOME: $(gnome-shell --version 2>/dev/null || echo unknown)"
  echo "Session: ${XDG_SESSION_TYPE:-unknown}"
  echo "Theme: $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo unknown)"
  echo "Icons: $(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo unknown)"
  echo "Plymouth: $(plymouth-set-default-theme 2>/dev/null || echo unknown)"
  gnome-extensions list | grep -E 'dash2dock|blur-my-shell|appindicatorsupport' || true
}

main(){
  acquire_lock
  case "$ACTION" in
    rollback) rollback; exit;;
    uninstall) uninstall; exit;;
    doctor) doctor; exit;;
  esac
  check_platform
  check_resources
  backup
  install_deps
  sync_sources
  install_tahoe
  install_dash2dock_animated
  install_blur
  install_appindicator
  make_wallpaper
  make_logo
  install_plymouth
  configure_grub
  configure_gdm
  configure_user
  configure_extensions
  configure_performance
  verify
  info "$PROJECT $VERSION completed. Log: $LOG_FILE"
  info "Log out and back in (or reboot) to activate GNOME Shell/GDM changes."
}

main "$@"
