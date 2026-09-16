#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="0.1.0"; PROJECT="MacOSify"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"; BACKUP_DIR="$STATE_DIR/backups"; LOG_FILE="$STATE_DIR/macosify.log"; LOCK_FILE="$STATE_DIR/install.lock"
DRY_RUN=0; SAFE_MODE=0; PERFORMANCE="auto"; PRESET="auto"; ACTION="install"
mkdir -p "$STATE_DIR" "$BACKUP_DIR"; exec > >(tee -a "$LOG_FILE") 2>&1
info(){ printf '[MacOSify] %s\n' "$*"; }; warn(){ printf '[MacOSify][WARN] %s\n' "$*" >&2; }; die(){ printf '[MacOSify][ERROR] %s\n' "$*" >&2; exit 1; }
run(){ if ((DRY_RUN)); then printf '+ '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }
usage(){ cat <<'EOF'
MacOSify - macOS-inspired Ubuntu GNOME desktop transformer
Usage: macosify.sh [options]
  --dry-run                 Show planned changes without applying them
  --safe-mode               Conservative desktop configuration
  --performance MODE        auto|low|balanced|quality
  --preset NAME             auto|sonoma|ventura|monterey|bigsur
  --repair                  Repair/reapply configuration
  --update                  Update managed theme sources
  --rollback                Restore latest backup
  --uninstall               Restore settings
  --version                 Show version
  -h, --help                Show help
EOF
}
while (($#)); do case "$1" in
--dry-run) DRY_RUN=1;; --safe-mode) SAFE_MODE=1;; --performance=*) PERFORMANCE="${1#*=}";; --performance) shift; PERFORMANCE="${1:-auto}";; --preset=*) PRESET="${1#*=}";; --preset) shift; PRESET="${1:-auto}";; --repair) ACTION=repair;; --update) ACTION=update;; --rollback) ACTION=rollback;; --uninstall) ACTION=uninstall;; --version) echo "$PROJECT $VERSION"; exit 0;; -h|--help) usage; exit 0;; *) die "Unknown option: $1";; esac; shift; done
acquire_lock(){ [[ -e "$LOCK_FILE" ]] && die "Another MacOSify operation is active."; printf '%s\n' "$$" > "$LOCK_FILE"; trap 'rm -f "$LOCK_FILE"' EXIT; }
check_platform(){ [[ -r /etc/os-release ]] || die "Cannot identify Linux distribution."; source /etc/os-release; [[ "${ID:-}" == ubuntu || "${ID_LIKE:-}" == *ubuntu* ]] || die "Ubuntu-based system required: ${PRETTY_NAME:-unknown}"; command -v gnome-shell >/dev/null || die "GNOME Shell is required."; GV="$(gnome-shell --version | awk '{print $3}')"; info "Detected ${PRETTY_NAME:-Ubuntu} | GNOME $GV | ${XDG_SESSION_TYPE:-unknown}"; }
check_resources(){ local mem; mem="$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)"; info "RAM ${mem}MB"; if [[ $PERFORMANCE == auto ]]; then if ((mem<4096)); then PERFORMANCE=low; elif ((mem<8192)); then PERFORMANCE=balanced; else PERFORMANCE=quality; fi; fi; case "$PERFORMANCE" in low|balanced|quality) ;; *) die "Invalid performance mode: $PERFORMANCE";; esac; info "Performance: $PERFORMANCE"; }
backup(){ local stamp="$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)"; run mkdir -p "$stamp"; ((DRY_RUN)) && return; dconf dump /org/gnome/ > "$stamp/gnome.dconf" || true; cp -a "$HOME/.config/gtk-3.0" "$stamp/gtk-3.0" 2>/dev/null || true; cp -a "$HOME/.config/gtk-4.0" "$stamp/gtk-4.0" 2>/dev/null || true; printf '%s\n' "$stamp" > "$STATE_DIR/latest-backup"; info "Backup: $stamp"; }
install_packages(){ info "Installing dependencies"; local p=(git curl ca-certificates unzip gsettings-desktop-schemas); command -v gnome-extensions >/dev/null || p+=(gnome-shell-extension-prefs); run sudo apt-get update; run sudo apt-get install -y "${p[@]}"; }
clone_sources(){ local b="$HOME/.local/share/macosify/sources"; run mkdir -p "$b"; ((DRY_RUN)) && return; for repo in WhiteSur-gtk-theme WhiteSur-icon-theme WhiteSur-cursors WhiteSur-wallpapers; do if [[ -d "$b/$repo/.git" ]]; then git -C "$b/$repo" pull --ff-only; else git clone --depth=1 "https://github.com/vinceliuice/$repo.git" "$b/$repo"; fi; done; }
install_themes(){ local b="$HOME/.local/share/macosify/sources"; ((DRY_RUN)) && { info "Would install WhiteSur assets"; return; }; bash "$b/WhiteSur-gtk-theme/install.sh" -c Light -c Dark || true; bash "$b/WhiteSur-icon-theme/install.sh" -a || true; bash "$b/WhiteSur-cursors/install.sh" -a || true; bash "$b/WhiteSur-wallpapers/install.sh" || true; }
configure(){ ((DRY_RUN)) && return; gsettings set org.gnome.desktop.interface gtk-theme WhiteSur-Light 2>/dev/null || true; gsettings set org.gnome.desktop.interface icon-theme WhiteSur 2>/dev/null || true; gsettings set org.gnome.desktop.interface cursor-theme WhiteSur-cursors 2>/dev/null || true; gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true; if gsettings list-schemas | grep -q '^org.gnome.shell.extensions.dash-to-dock$'; then gsettings set org.gnome.shell.extensions.dash-to-dock dock-position BOTTOM || true; gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false || true; gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false || true; gsettings set org.gnome.shell.extensions.dash-to-dock autohide true || true; fi; }
verify(){ command -v gsettings >/dev/null || die "gsettings missing"; command -v gnome-shell >/dev/null || die "gnome-shell missing"; info "GTK: $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo unknown)"; info "Icons: $(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo unknown)"; info "Verification passed"; }
rollback(){ [[ -f "$STATE_DIR/latest-backup" ]] || die "No MacOSify backup found."; local b; b="$(cat "$STATE_DIR/latest-backup")"; ((DRY_RUN)) && { info "Would restore $b"; return; }; [[ -s "$b/gnome.dconf" ]] && dconf load /org/gnome/ < "$b/gnome.dconf" || true; info "Restored GNOME settings from $b"; }
uninstall(){ rollback || true; ((DRY_RUN)) && return; gsettings reset org.gnome.desktop.interface gtk-theme 2>/dev/null || true; gsettings reset org.gnome.desktop.interface icon-theme 2>/dev/null || true; gsettings reset org.gnome.desktop.interface cursor-theme 2>/dev/null || true; info "MacOSify settings reset."; }
main(){ acquire_lock; check_platform; check_resources; case "$ACTION" in rollback) rollback;; uninstall) uninstall;; install|repair|update) backup; install_packages; clone_sources; install_themes; configure; verify;; *) die "Invalid action";; esac; info "$PROJECT $VERSION complete."; }
main "$@"