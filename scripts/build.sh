#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="FastInternetSummary.app"
derived="${DERIVED_DATA_PATH:-$root/build}"
built="$derived/Build/Products/Release/$app_name"

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
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  build

if [[ ! -d "$built" ]]; then
  echo "Build finished but $app_name was not found at $built." >&2
  exit 1
fi
