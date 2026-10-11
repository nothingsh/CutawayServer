#!/bin/bash
# Generates the Swift code for the pinned schema.
# Usage: generate-wire.sh [output-dir]   (default: Sources/CutawayWire/Generated)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

fail() {
  echo "generate-wire: $1" >&2
  exit 1
}

out="${1:-$repo_root/Sources/CutawayWire/Generated}"
[[ "$out" == /* ]] || out="$PWD/$out"
# The output directory is replaced as a whole, so it must be new, empty, or a previous output.
if [[ -e "$out" ]]; then
  [[ -d "$out" ]] || fail "$out is not a directory"
  if [[ -n "$(ls -A "$out" | grep -vxE 'cutaway_generated\.swift|\.DS_Store' || true)" ]]; then
    fail "refusing to replace $out: it holds files this script did not write"
  fi
fi

flatc="$("$repo_root/Protocol/scripts/get-flatc.sh" "$repo_root/.tools")" ||
  fail "could not install the pinned flatc"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
"$flatc" --swift --gen-object-api -o "$work" "$repo_root/Protocol/schema/cutaway.fbs" ||
  fail "flatc failed"
file="$work/cutaway_generated.swift"
[[ -f "$file" ]] || fail "flatc did not write cutaway_generated.swift"

# Four changes to flatc's output:
# 1. Drop the conditional import of Common: its sources are part of CutawayFlatBuffers,
#    and a host app may have an unrelated module named Common.
# 2. Import the renamed runtime, internally.
# 3. Make every declaration internal. Together with the internal import, the compiler
#    then rejects any public CutawayWire API that exposes a FlatBuffers type.
# 4. Compile the file only where the server is compiled, or on platforms without UIKit, so
#    that a Release host without the trait gets none of it (S-REL-01). The same condition
#    wraps every hand-written file of CutawayWire.
condition='#if !canImport(UIKit) || DEBUG || ReleaseEnabled'
CONDITION="$condition" /usr/bin/perl -0pi -e '
  s/#if canImport\(Common\)\nimport Common\n#endif\n\n// or die "no Common import block\n";
  s/^import FlatBuffers$/internal import CutawayFlatBuffers/m or die "no FlatBuffers import\n";
  s/^([ \t]*)public /$1/mg or die "no public declarations\n";
  s/\A/$ENV{CONDITION}\n/;
  s/\n?\z/\n#endif\n/;
' "$file" || fail "flatc's output no longer has the expected shape"

grep -qx 'internal import CutawayFlatBuffers' "$file" ||
  fail "the generated code does not import CutawayFlatBuffers"
offenders="$(grep -nE 'canImport|^[[:space:]]*import (Common|FlatBuffers)[[:space:]]*$|(^|[^[:alnum:]_])public([^[:alnum:]_]|$)' "$file" |
  grep -vF "$condition" || true)"
[[ -z "$offenders" ]] || {
  echo "$offenders"
  fail "the generated code still refers to upstream modules or declares public API"
}
[[ "$(head -1 "$file")" == "$condition" && "$(tail -1 "$file")" == "#endif" ]] ||
  fail "the generated code is not wrapped in the compilation condition"

rm -rf "$out"
mkdir -p "$out"
cp "$file" "$out/cutaway_generated.swift"
echo "generate-wire: wrote $out/cutaway_generated.swift"
