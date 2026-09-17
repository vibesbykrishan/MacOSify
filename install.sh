#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPO='https://github.com/vibesbykrishan/MacOSify.git'
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ "$(id -u)" -eq 0 ]]; then
  echo 'Run this as your normal Ubuntu user, not root.' >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo 'MacOSify currently requires Ubuntu/Debian apt.' >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo '[MacOSify] curl not found — installing it automatically...'
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl
fi

if ! command -v git >/dev/null 2>&1; then
  echo '[MacOSify] git not found — installing it automatically...'
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git
fi

echo '[MacOSify] Downloading the latest installer...'
git clone --depth=1 "$REPO" "$TMP/MacOSify" >/dev/null 2>&1
# Keep the historical core installer compatible while presenting one coherent release version.
sed -i 's/VERSION="1\.3\.0"/VERSION="1.8.0"/; s/MacOSify 1\.3 -/MacOSify 1.8 -/' "$TMP/MacOSify/macosify.sh"
bash "$TMP/MacOSify/macosify.sh" "$@"
if [[ -f "$TMP/MacOSify/macosify-enhance.sh" ]]; then
  bash "$TMP/MacOSify/macosify-enhance.sh"
fi
if [[ -f "$TMP/MacOSify/macosify-finalize.sh" ]]; then
  bash "$TMP/MacOSify/macosify-finalize.sh"
fi
if [[ -f "$TMP/MacOSify/macosify-boot-theme.sh" ]]; then
  bash "$TMP/MacOSify/macosify-boot-theme.sh"
fi
