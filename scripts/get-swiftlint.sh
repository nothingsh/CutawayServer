#!/bin/bash
# Installs the pinned SwiftLint and prints its path.
# Usage: get-swiftlint.sh [destination-dir]   (default: <repo>/.tools)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
version="$(tr -d '[:space:]' <"$script_dir/SWIFTLINT_VERSION")"
dest="${1:-$repo_root/.tools}"
swiftlint="$dest/swiftlint"

fail() {
  echo "get-swiftlint: $1" >&2
  exit 1
}

if [[ -x "$swiftlint" ]] && [[ "$("$swiftlint" --version)" == "$version" ]]; then
  echo "$swiftlint"
  exit 0
fi

# One line per version: "<sha256 of portable_swiftlint.zip>  <version>".
expected_sha="$(awk -v v="$version" '$2 == v { print $1 }' "$script_dir/SWIFTLINT_SHA256")"
[[ -n "$expected_sha" ]] || fail "no checksum for version $version in SWIFTLINT_SHA256"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A universal binary (arm64 and x86_64).
url="https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip"
curl --fail --location --silent --show-error -o "$work/portable_swiftlint.zip" "$url" ||
  fail "download failed: $url"

actual_sha="$(shasum -a 256 "$work/portable_swiftlint.zip" | awk '{ print $1 }')"
[[ "$actual_sha" == "$expected_sha" ]] ||
  fail "checksum mismatch for portable_swiftlint.zip $version: expected $expected_sha, got $actual_sha"

unzip -q "$work/portable_swiftlint.zip" -d "$work"
[[ -f "$work/swiftlint" ]] || fail "archive does not contain swiftlint"

mkdir -p "$dest"
mv "$work/swiftlint" "$swiftlint"
chmod +x "$swiftlint"

actual_version="$("$swiftlint" --version)"
[[ "$actual_version" == "$version" ]] ||
  fail "installed swiftlint reports '$actual_version', expected '$version'"

echo "$swiftlint"
