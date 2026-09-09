#!/usr/bin/env bash
# Install Ookla's official Speedtest CLI if this Mac does not already have it.
# Homebrew when present; otherwise the universal macOS tarball from Ookla.
# Keep the URL, version, and SHA256 in sync with OoklaCLI.swift.
set -euo pipefail

url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-macosx-universal.tgz"
expected_sha256="c9f8192149ebc88f8699998cecab1ce144144045907ece6f53cf50877f4de66f"
support_bin="$HOME/Library/Application Support/com.danielku.FastInternetSummary/bin/speedtest"

is_official_cli() {
  local bin="$1"
  [[ -x "$bin" ]] || return 1
  local kind
  kind="$(file -b "$bin" 2>/dev/null || true)"
  [[ "$kind" == *Mach-O* ]]
}

official_path() {
  local candidate
  for candidate in \
    /opt/homebrew/bin/speedtest \
    /usr/local/bin/speedtest \
    "$support_bin"
  do
    if is_official_cli "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

install_with_brew() {
  command -v brew >/dev/null 2>&1 || return 1
  NONINTERACTIVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew tap teamookla/speedtest \
    && NONINTERACTIVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew install teamookla/speedtest/speedtest
}

install_from_ookla() {
  command -v curl >/dev/null 2>&1 || {
    echo "curl is required to download Speedtest CLI." >&2
    return 1
  }
  local dest_dir work archive actual
  dest_dir="$(dirname "$support_bin")"
  mkdir -p "$dest_dir"
  work="$(mktemp -d "${TMPDIR:-/tmp}/fis-speedtest.XXXXXX")"
  archive="$work/speedtest.tgz"

  curl -fsSL --retry 3 "$url" -o "$archive" || { rm -rf "$work"; return 1; }
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual" != "$expected_sha256" ]]; then
    echo "Speedtest CLI download did not match the expected checksum." >&2
    rm -rf "$work"
    return 1
  fi
  tar -xzf "$archive" -C "$work" || { rm -rf "$work"; return 1; }
  if [[ ! -f "$work/speedtest" ]]; then
    echo "Speedtest CLI archive did not contain a speedtest binary." >&2
    rm -rf "$work"
    return 1
  fi
  install -m 755 "$work/speedtest" "$support_bin" || { rm -rf "$work"; return 1; }
  xattr -dr com.apple.quarantine "$support_bin" 2>/dev/null || true
  rm -rf "$work"
}

if path="$(official_path)"; then
  echo "Speedtest CLI already installed at $path"
  exit 0
fi

if install_with_brew && path="$(official_path)"; then
  echo "Installed Speedtest CLI with Homebrew at $path"
  exit 0
fi

echo "Downloading Speedtest CLI from Ookla..."
install_from_ookla
path="$(official_path)"
echo "Installed Speedtest CLI at $path"
