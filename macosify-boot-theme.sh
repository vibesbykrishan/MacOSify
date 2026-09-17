#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macosify"
mkdir -p "$STATE_DIR"

info(){ printf '[MacOSify][Boot] %s\n' "$*"; }
warn(){ printf '[MacOSify][Boot][WARN] %s\n' "$*" >&2; }

if ! command -v sudo >/dev/null 2>&1; then
  warn 'sudo is unavailable; boot theme not changed.'
  exit 0
fi
sudo -v || { warn 'Sudo authentication failed; boot theme not changed.'; exit 0; }

api='https://api.opendesktop.org/ocs/v1/content/data/2071982'
xml="$STATE_DIR/macos-majave-2071982.xml"
work="$STATE_DIR/macos-majave-light-2x"
mkdir -p "$work"

curl -fsSL --retry 3 --connect-timeout 15 "$api" -o "$xml" || { warn 'Could not fetch Gnome-Look metadata.'; exit 0; }
url="$(python3 - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot()
content=root.find('.//content')
for node in content:
    if node.tag.startswith('downloadlink') and 'LIGHT-2X' in (node.text or '').upper() and (node.text or '').upper().endswith('.ZIP'):
        print(node.text); break
PY
)"
[[ -n "$url" ]] || { warn 'Could not find the LIGHT-2X Plymouth package.'; exit 0; }

rm -rf "$work/unpacked"
mkdir -p "$work/unpacked"
curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$work/theme.zip" || { warn 'Plymouth package download failed.'; exit 0; }
unzip -q "$work/theme.zip" -d "$work/unpacked"

src="$(find "$work/unpacked" -type f -name '*PLYMOUTH-THEME.plymouth' -print -quit | xargs -r dirname)"
[[ -n "$src" && -d "$src" ]] || { warn 'Plymouth package layout was not recognized.'; exit 0; }

dest='/usr/share/plymouth/themes/macos-majave-light-2x'
sudo rm -rf "$dest"
sudo mkdir -p "$dest"
sudo cp -a "$src"/. "$dest"/

plymouth_file="$(find "$dest" -maxdepth 1 -type f -name '*.plymouth' -print -quit)"
script_file="$(find "$dest" -maxdepth 1 -type f -name '*.script' -print -quit)"
[[ -n "$plymouth_file" && -n "$script_file" ]] || { warn 'Plymouth files were not found after extraction.'; exit 0; }

final_plymouth="$dest/macos-majave-light-2x.plymouth"
final_script="$dest/macos-majave-light-2x.script"
sudo mv "$plymouth_file" "$final_plymouth"
sudo mv "$script_file" "$final_script"
sudo sed -i "s|^ImageDir=.*|ImageDir=$dest|; s|^ScriptFile=.*|ScriptFile=$final_script|" "$final_plymouth"

sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$final_plymouth" 250
sudo update-alternatives --set default.plymouth "$final_plymouth"
sudo update-initramfs -u -k all

info 'Installed MACOS-MAJAVE-BOOT-SPLASH-PORT LIGHT 2X (Gnome-Look p/2071982).'
info "Active Plymouth: $(readlink -f /etc/alternatives/default.plymouth)"
