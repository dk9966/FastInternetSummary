#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="FastInternetSummary.app"
derived="$root/build"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode from the App Store, open it once, then run this again." >&2
  exit 1
fi

echo "Building Fast Internet Summary (Release)..."
xcodebuild \
  -project "$root/FastInternetSummary.xcodeproj" \
  -scheme FastInternetSummary \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived" \
  build

built="$derived/Build/Products/Release/$app_name"
if [[ ! -d "$built" ]]; then
  echo "Build finished but $app_name was not found at $built." >&2
  exit 1
fi

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
cp -R "$built" "$dest"
xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

open "$dest"

echo "Installed to $dest"
echo "Look for the plug/antenna icon in the menu bar. Click it, or press Option-Command-Period."
