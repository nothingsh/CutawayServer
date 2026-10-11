#!/bin/bash
# Rebuilds the vendored FlatBuffers Swift runtime from the pinned upstream release.
# Usage: vendor-flatbuffers.sh [destination-dir]   (default: Sources/CutawayFlatBuffers)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
version="$(tr -d '[:space:]' <"$repo_root/Protocol/FLATBUFFERS_VERSION")"
archive="$repo_root/.tools/flatbuffers-$version.tar.gz"
url="https://github.com/google/flatbuffers/archive/refs/tags/v$version.tar.gz"
marker="// CutawayServer: upstream imports its Common module here; those sources are compiled into this module instead."

fail() {
  echo "vendor-flatbuffers: $1" >&2
  exit 1
}
sha_of() { shasum -a 256 "$1" | awk '{ print $1 }'; }

dest="${1:-$repo_root/Sources/CutawayFlatBuffers}"
[[ "$dest" == /* ]] || dest="$PWD/$dest"
# The destination is replaced as a whole, so it must be new, empty, or a previous output.
if [[ -e "$dest" ]]; then
  [[ -d "$dest" ]] || fail "$dest is not a directory"
  if [[ -n "$(ls -A "$dest")" ]] && [[ ! -f "$dest/UPSTREAM" ]]; then
    fail "refusing to replace $dest: it is not empty and has no UPSTREAM file, so this script did not write it"
  fi
fi

expected_sha="$(awk -v v="$version" '$2 == v { print $1 }' "$script_dir/FLATBUFFERS_SOURCE_SHA256")"
[[ -n "$expected_sha" ]] || fail "no checksum for $version in scripts/FLATBUFFERS_SOURCE_SHA256"

if [[ ! -f "$archive" ]] || [[ "$(sha_of "$archive")" != "$expected_sha" ]]; then
  mkdir -p "$(dirname "$archive")"
  curl --fail --location --silent --show-error -o "$archive.part" "$url" ||
    fail "download failed: $url"
  actual_sha="$(sha_of "$archive.part")"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    rm -f "$archive.part"
    fail "checksum mismatch for $url: expected $expected_sha, got $actual_sha"
  fi
  mv "$archive.part" "$archive"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
prefix="flatbuffers-$version/swift"
tar -xzf "$archive" -C "$work" \
  "$prefix/Sources/FlatBuffers" "$prefix/Sources/Common" "$prefix/LICENSE" ||
  fail "the archive does not have the expected layout"

# Only the Swift sources: upstream's documentation catalog is left out.
stage="$work/stage"
mkdir -p "$stage"
while IFS= read -r -d '' file; do
  mkdir -p "$stage/$(dirname "$file")"
  cp "$work/$prefix/Sources/$file" "$stage/$file"
done < <(cd "$work/$prefix/Sources" &&
  find FlatBuffers Common -name '*.swift' -not -path '*/Documentation.docc/*' -print0)
cp "$work/$prefix/LICENSE" "$stage/LICENSE"

# The first change to upstream: both source directories become one module, so the
# conditional import of Common goes away. A host app may have its own module named
# Common; leaving the check in would make this code depend on the host.
find "$stage" -name '*.swift' -print0 |
  MARKER="$marker" xargs -0 /usr/bin/perl -0pi -e \
    's/#if canImport\(Common\)\nimport Common\n#endif\n/$ENV{MARKER}\n/g'

# The second change: each file is compiled only where the server is compiled, or on
# platforms without UIKit, so that a Release host without the trait gets none of the
# runtime (S-REL-01). The same condition wraps every file of CutawayWire.
condition='#if !canImport(UIKit) || DEBUG || ReleaseEnabled'
find "$stage" -name '*.swift' -print0 |
  CONDITION="$condition" xargs -0 /usr/bin/perl -0pi -e \
    's/\A/$ENV{CONDITION}\n/; s/\n?\z/\n#endif\n/'

if grep -rnE 'canImport\((Common|FlatBuffers)\)|^[[:space:]]*import (Common|FlatBuffers)[[:space:]]*$' "$stage"; then
  fail "the upstream sources import modules in a way this script does not handle"
fi
replaced="$({ grep -rlF "$marker" "$stage" || true; } | wc -l | tr -d '[:space:]')"
[[ "$replaced" -gt 0 ]] || fail "found no Common import to replace; the upstream layout changed"
version_function="FlatBuffersVersion_${version//./_}"
grep -q "func $version_function()" "$stage/FlatBuffers/Constants.swift" ||
  fail "the runtime does not declare $version_function"

cat >"$stage/UPSTREAM" <<EOF
FlatBuffers Swift runtime $version
Source:  $url
SHA-256: $expected_sha
Paths:   swift/Sources/FlatBuffers and swift/Sources/Common (*.swift only), swift/LICENSE

Changes from upstream, applied by scripts/vendor-flatbuffers.sh:
- Both source directories are compiled into the single module CutawayFlatBuffers.
- Each "#if canImport(Common) / import Common / #endif" block is replaced by a
  one-line comment ($replaced files).
- Each file is wrapped in "$condition" ... "#endif", so that it is compiled only
  where CutawayServer is, or on platforms without UIKit.

Do not edit these files by hand. scripts/verify.sh rebuilds this directory and compares.
EOF

rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
cp -R "$stage" "$dest"
count="$(find "$dest" -name '*.swift' | wc -l | tr -d '[:space:]')"
echo "vendor-flatbuffers: wrote $count Swift files to $dest"
