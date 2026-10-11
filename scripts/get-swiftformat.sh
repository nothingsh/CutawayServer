#!/bin/bash
# Installs the pinned SwiftFormat and prints its path.
# Usage: get-swiftformat.sh [destination-dir]   (default: <repo>/.tools)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
version="$(tr -d '[:space:]' <"$script_dir/SWIFTFORMAT_VERSION")"
dest="${1:-$repo_root/.tools}"
swiftformat="$dest/swiftformat"

fail() {
  echo "get-swiftformat: $1" >&2
  exit 1
}

if [[ -x "$swiftformat" ]] && [[ "$("$swiftformat" --version)" == "$version" ]]; then
  echo "$swiftformat"
  exit 0
fi

# One line per version: "<sha256 of swiftformat.zip>  <version>".
expected_sha="$(awk -v v="$version" '$2 == v { print $1 }' "$script_dir/SWIFTFORMAT_SHA256")"
[[ -n "$expected_sha" ]] || fail "no checksum for version $version in SWIFTFORMAT_SHA256"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A universal binary (arm64 and x86_64).
url="https://github.com/nicklockwood/SwiftFormat/releases/download/$version/swiftformat.zip"
curl --fail --location --silent --show-error -o "$work/swiftformat.zip" "$url" ||
  fail "download failed: $url"

actual_sha="$(shasum -a 256 "$work/swiftformat.zip" | awk '{ print $1 }')"
[[ "$actual_sha" == "$expected_sha" ]] ||
  fail "checksum mismatch for swiftformat.zip $version: expected $expected_sha, got $actual_sha"

unzip -q "$work/swiftformat.zip" -d "$work"
[[ -f "$work/swiftformat" ]] || fail "archive does not contain swiftformat"

mkdir -p "$dest"
mv "$work/swiftformat" "$swiftformat"
chmod +x "$swiftformat"

actual_version="$("$swiftformat" --version)"
[[ "$actual_version" == "$version" ]] ||
  fail "installed swiftformat reports '$actual_version', expected '$version'"

echo "$swiftformat"
