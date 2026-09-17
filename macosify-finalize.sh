#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.8.0"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"
SOURCE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/macosify/sources"
THEME_SCRIPT="${BASH_SOURCE[0]%/*}/macosify-theme.sh"
mkdir -p "$STATE_DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"

info(){ printf '[MacOSify] %s\n' "$*"; }
warn(){ printf '[MacOSify][WARN] %s\n' "$*" >&2; }

if [[ -S "/run/user/$(id -u)/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

set_schema(){
  local dir="$1" schema="$2" key="$3" value="$4"
  [[ -d "$dir" ]] || return 0
  GSETTINGS_SCHEMA_DIR="$dir" gsettings set "$schema" "$key" "$value" 2>/dev/null || true
}

apply_light_glass(){
  local blur="$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas"
  local dock="$HOME/.local/share/gnome-shell/extensions/dash2dock-lite@icedman.github.com/schemas"
  local user="$HOME/.local/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com/schemas"
  gsettings set org.gnome.desktop.interface gtk-theme MacTahoe-Light 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme prefer-light 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme MacTahoe 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme MacTahoe-cursors 2>/dev/null || true
  set_schema "$user" org.gnome.shell.extensions.user-theme name MacTahoe-Light

  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.panel style-panel 1
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.panel brightness 1.0
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.panel color '(1.0,1.0,1.0,0.72)'
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.panel override-background true
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.panel static-blur true
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.popup style-popup 1
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.popup preserve-shell-theme false
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.popup corner-radius 24
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.popup menu-corner-radius 24
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.popup quick-settings-corner-radius 30
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.popup notification-corner-radius 20
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.popup osd-corner-radius 24
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.popup dialog-corner-radius 20
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock 1
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.dash-to-dock brightness 1.0
  set_schema "$blur" org.gnome.shell.extensions.blur-my-shell.dash-to-dock static-blur true

  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite background-color '(1.0,1.0,1.0,0.72)'
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite blur-background true
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite border-radius 28
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite border-thickness 0
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite autohide-dash true
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite autohide-dodge true
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite apps-icon true
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite apps-icon-front true
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite trash-icon true
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite pressure-sense true
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite pressure-sense-sensitivity 0.35
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite edge-distance 0.015
  set_schema "$dock" org.gnome.shell.extensions.dash2dock-lite icon-size 48
}

apply_reveal_behavior(){
  local hide="$HOME/.local/share/gnome-shell/extensions/hidetopbar@mathieu.bidon.ca/schemas"
  set_schema "$hide" org.gnome.shell.extensions.hidetopbar enable-intellihide true
  set_schema "$hide" org.gnome.shell.extensions.hidetopbar enable-active-window true
  set_schema "$hide" org.gnome.shell.extensions.hidetopbar mouse-sensitive true
  set_schema "$hide" org.gnome.shell.extensions.hidetopbar mouse-sensitive-fullscreen-window true
  set_schema "$hide" org.gnome.shell.extensions.hidetopbar animation-time-autohide 0.20
  gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface gtk-decoration-layout 'close,minimize,maximize:' 2>/dev/null || true
}

patch_shell_css(){
  local theme="$HOME/.themes/MacTahoe-Light/gnome-shell/gnome-shell.css"
  [[ -f "$theme" ]] || return 0
  local marker='/* MacOSify Tahoe Liquid Glass v1.8 */'
  grep -Fq "$marker" "$theme" && return 0
  cat >>"$theme" <<'CSS'

/* MacOSify Tahoe Liquid Glass v1.8 */
#panel { background-color: rgba(254,254,254,0.75) !important; color: #424242 !important; }
#panel .panel-corner { -panel-corner-background-color: rgba(254,254,254,0.75) !important; }
#panel .panel-button { color: #424242 !important; }
#panel .panel-button:hover, #panel .panel-button:active, #panel .panel-button:checked { color: #202020 !important; }
.popup-menu-content { background-color: rgba(254,254,254,0.94) !important; border-radius: 24px !important; }
.popup-menu-boxpointer { -arrow-border-radius: 24px !important; }
CSS
}

install_theme_center(){
  [[ -f "$THEME_SCRIPT" ]] || return 0
  install -m 0755 "$THEME_SCRIPT" "$HOME/.local/bin/macosify-theme"
  cat >"$HOME/.local/bin/theme" <<'EOF'
#!/usr/bin/env bash
exec "$HOME/.local/bin/macosify-theme" "${1:-change}" "${@:2}"
EOF
  chmod 0755 "$HOME/.local/bin/theme"
  cat >"$HOME/.local/share/applications/MacOSify-Theme-Center.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=MacOSify Theme Center
Comment=Switch MacTahoe Light, Dark and accent themes
Icon=preferences-desktop-theme
Terminal=true
Exec=$HOME/.local/bin/theme change
Categories=Settings;DesktopSettings;
StartupNotify=true
EOF
  chmod 0644 "$HOME/.local/share/applications/MacOSify-Theme-Center.desktop"
}

install_boot_theme(){
  command -v sudo >/dev/null 2>&1 || { warn 'sudo unavailable; boot theme skipped.'; return 0; }
  if ! sudo -n true 2>/dev/null; then
    warn 'Sudo authentication is required once to install the Mojave Plymouth boot theme.'
    sudo -v || { warn 'Could not authenticate sudo; boot theme will be applied on the next run.'; return 0; }
  fi
  local api xml url work src dest file script
  api='https://api.opendesktop.org/ocs/v1/content/data/2071982'
  xml="$STATE_DIR/macos-majave-2071982.xml"
  curl -fsSL --retry 3 --connect-timeout 15 "$api" -o "$xml" || { warn 'Could not read the requested Gnome-Look theme metadata.'; return 0; }
  url="$(python3 - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot()
content=root.find('.//content')
for node in content:
    if node.tag.startswith('downloadlink') and (node.text or '').endswith('LIGHT-2X-V1.0-PLYMOUTH-THEME.ZIP'):
        print(node.text); break
PY
)"
  [[ -n "$url" ]] || { warn 'Light 2X Plymouth download was not found.'; return 0; }
  work="$STATE_DIR/macos-majave-light-2x"
  rm -rf "$work"
  mkdir -p "$work"
  curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$work/theme.zip" || { warn 'Plymouth theme download failed.'; return 0; }
  unzip -q "$work/theme.zip" -d "$work/unpacked"
  src="$(find "$work/unpacked" -type f -name '*LIGHT-2X*plymouth-theme.plymouth' -print -quit | xargs -r dirname)"
  [[ -n "$src" && -d "$src" ]] || { warn 'Downloaded Plymouth archive layout was not recognized.'; return 0; }
  dest='/usr/share/plymouth/themes/macos-majave-light-2x'
  file="$dest/macos-majave-light-2x.plymouth"
  script="$dest/macos-majave-light-2x.script"
  sudo rm -rf "$dest"
  sudo mkdir -p "$dest"
  sudo cp -a "$src"/. "$dest"/
  local original_plymouth original_script
  original_plymouth="$(find "$dest" -maxdepth 1 -type f -name '*.plymouth' -print -quit)"
  original_script="$(find "$dest" -maxdepth 1 -type f -name '*.script' -print -quit)"
  [[ -n "$original_plymouth" && -n "$original_script" ]] || { warn 'Plymouth files missing after extraction.'; return 0; }
  sudo mv "$original_plymouth" "$file"
  sudo mv "$original_script" "$script"
  sudo sed -i "s|^ImageDir=.*|ImageDir=$dest|; s|^ScriptFile=.*|ScriptFile=$script|" "$file"
  sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$file" 250
  sudo update-alternatives --set default.plymouth "$file"
  sudo update-initramfs -u -k all
  info 'Mojave Light 2X Plymouth theme installed and initramfs rebuilt.'
}

verify(){
  echo '=== MacOSify 1.8 FINAL CHECK ==='
  echo "GTK=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true)"
  echo "COLOR=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"
  echo "WINDOW=$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null || true)"
  echo "PLYMOUTH=$(readlink -f /etc/alternatives/default.plymouth 2>/dev/null || true)"
  echo "THEME_CENTER=$HOME/.local/bin/theme change"
  [[ -x "$HOME/.local/bin/theme" ]] && echo 'THEME_SWITCHER=OK'
}

install_theme_center
apply_light_glass
apply_reveal_behavior
patch_shell_css
install_boot_theme
verify
info "MacOSify $VERSION finalization complete. Log out/in or reboot once to reload the GNOME Shell theme fully."
