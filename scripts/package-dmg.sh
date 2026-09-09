#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="FastInternetSummary.app"
built="$root/build/Build/Products/Release/$app_name"
dist="${DIST_DIR:-$root/dist}"
volume_name="Fast Internet Summary"
dmg_path="$dist/FastInternetSummary.dmg"
iconset_dir="$root/FastInternetSummary/Assets.xcassets/AppIcon.appiconset"

window_w=600
window_h=400
icon_size=128
app_x=150
app_y=190
apps_x=450
apps_y=190

bash "$root/scripts/build.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/fis-dmg.XXXXXX")"
stage="$work/stage"
rw_dmg="$work/rw.dmg"
mount_point=""

cleanup() {
  if [[ -n "$mount_point" ]]; then
    hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$dist" "$stage/.background"
rm -f "$dmg_path"

ditto "$built" "$stage/$app_name"
ln -s /Applications "$stage/Applications"
xattr -cr "$stage/$app_name" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$stage/$app_name"

swift "$root/scripts/render-dmg-background.swift" \
  "$stage/.background/background.png" \
  "$window_w" \
  "$window_h"

iconset="$work/VolumeIcon.iconset"
mkdir -p "$iconset"
cp "$iconset_dir/icon_16.png"    "$iconset/icon_16x16.png"
cp "$iconset_dir/icon_32.png"    "$iconset/icon_16x16@2x.png"
cp "$iconset_dir/icon_32.png"    "$iconset/icon_32x32.png"
cp "$iconset_dir/icon_64.png"    "$iconset/icon_32x32@2x.png"
cp "$iconset_dir/icon_128.png"   "$iconset/icon_128x128.png"
cp "$iconset_dir/icon_256.png"   "$iconset/icon_128x128@2x.png"
cp "$iconset_dir/icon_256.png"   "$iconset/icon_256x256.png"
cp "$iconset_dir/icon_512.png"   "$iconset/icon_256x256@2x.png"
cp "$iconset_dir/icon_512.png"   "$iconset/icon_512x512.png"
cp "$iconset_dir/icon_1024.png"  "$iconset/icon_512x512@2x.png"
iconutil -c icns -o "$work/VolumeIcon.icns" "$iconset"

hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$stage" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "$rw_dmg" >/dev/null

hdiutil attach "$rw_dmg" -readwrite -noverify -noautoopen >/dev/null
mount_point="/Volumes/$volume_name"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -d "$mount_point" ]]; then
    break
  fi
  sleep 0.3
done
if [[ ! -d "$mount_point" ]]; then
  echo "Failed to mount the disk image." >&2
  exit 1
fi

if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "$mount_point/.background"
fi

# Classic drag-to-Applications window. Skip quietly if Finder is not available (CI).
# Finder's "update" can delete .VolumeIcon.icns, so the volume icon is copied after this.
if osascript >/dev/null 2>&1 <<EOF
tell application "Finder"
  tell disk "$volume_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 160, $((200 + window_w)), $((160 + window_h))}
    set theViewOptions to the icon view options of container window
    set icon size of theViewOptions to $icon_size
    set arrangement of theViewOptions to not arranged
    set background picture of theViewOptions to file ".background:background.png"
    delay 0.4
    set position of item "$app_name" to {$app_x, $app_y}
    set position of item "Applications" to {$apps_x, $apps_y}
    close
    open
    delay 1
    close
  end tell
end tell
EOF
then
  :
else
  echo "Finder layout skipped; the disk image still contains the app and an Applications shortcut."
fi

cp "$work/VolumeIcon.icns" "$mount_point/.VolumeIcon.icns"
if command -v SetFile >/dev/null 2>&1; then
  SetFile -c icnC "$mount_point/.VolumeIcon.icns"
  SetFile -a C "$mount_point"
fi
if [[ ! -f "$mount_point/.VolumeIcon.icns" ]]; then
  echo "Volume icon was not copied onto the disk image." >&2
  exit 1
fi

rm -rf "$mount_point/.fseventsd" || true
sync
if [[ "$(uname -m)" == "arm64" ]]; then
  bless --folder "$mount_point" >/dev/null 2>&1 || true
else
  bless --folder "$mount_point" --openfolder "$mount_point" >/dev/null 2>&1 || true
fi

for _ in 1 2 3 4 5 6; do
  if hdiutil detach "$mount_point" -quiet; then
    mount_point=""
    break
  fi
  sleep 1
done
if [[ -n "$mount_point" ]]; then
  echo "Could not unmount $mount_point" >&2
  exit 1
fi

hdiutil convert "$rw_dmg" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$dmg_path" >/dev/null

swift "$root/scripts/set-file-icon.swift" "$work/VolumeIcon.icns" "$dmg_path" \
  || echo "Could not set the disk image file icon; the .dmg is still usable."

echo "Wrote $dmg_path"
