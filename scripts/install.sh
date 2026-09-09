#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="FastInternetSummary.app"
built="$root/build/Build/Products/Release/$app_name"

bash "$root/scripts/build.sh"

dest_dir="${PREFIX:-/Applications}"
if [[ ! -d "$dest_dir" || ! -w "$dest_dir" ]]; then
  dest_dir="$HOME/Applications"
  mkdir -p "$dest_dir"
fi
dest="$dest_dir/$app_name"

if pgrep -x FastInternetSummary >/dev/null 2>&1; then
  osascript -e 'tell application "Fast Internet Summary" to quit' >/dev/null 2>&1 || true
  sleep 0.4
  if pgrep -x FastInternetSummary >/dev/null 2>&1; then
    pkill -x FastInternetSummary || true
    sleep 0.3
  fi
  if pgrep -x FastInternetSummary >/dev/null 2>&1; then
    pkill -9 -x FastInternetSummary || true
    sleep 0.2
  fi
fi

rm -rf "$dest"
ditto "$built" "$dest"
xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

if ! bash "$root/scripts/install-speedtest.sh"; then
  echo "Speedtest CLI could not be installed now. MacOS Network Quality still works, and the app will try again on launch." >&2
fi

open "$dest"

echo "Installed to $dest"
echo "Look for the plug/antenna icon in the menu bar. Click it, or press Option-Command-Period."
