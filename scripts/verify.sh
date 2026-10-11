#!/bin/bash
# The single acceptance gate for this repository.
# Usage: verify.sh [--mac-only]
#   --mac-only  stops before the steps that need a simulator (used by CI). Only a run without
#               it counts as verification.
set -euo pipefail

mac_only=""
case "${1:-}" in
  "") ;;
  --mac-only) mac_only=yes ;;
  *)
    echo "usage: scripts/verify.sh [--mac-only]" >&2
    exit 2
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

step() { printf '\n== %s\n' "$1"; }
fail() {
  echo "verify: FAILED: $1" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

step "protocol submodule"
[[ -f Protocol/PROTOCOL_VERSION ]] ||
  fail "Protocol/ is empty; run: git submodule update --init"
protocol_tag="$(git -C Protocol describe --tags --exact-match 2>/dev/null)" ||
  fail "Protocol/ must be checked out at a released tag (a shallow clone hides tags: git -C Protocol fetch --tags --unshallow)"
[[ -z "$(git -C Protocol status --porcelain)" ]] ||
  fail "Protocol/ has local modifications; it is read-only here"
git -C Protocol merge-base --is-ancestor HEAD origin/main 2>/dev/null ||
  fail "Protocol/ is at a commit that is not on the protocol repository's main branch"
[[ "$(git -C Protocol rev-parse HEAD)" == "$(git ls-files -s Protocol | awk '{ print $2 }')" ]] ||
  fail "Protocol/ is not at the commit this repository records; stage the new pin with: git add Protocol"
echo "protocol $(tr -d '[:space:]' <Protocol/PROTOCOL_VERSION) at $protocol_tag"

step "pinned flatc"
flatc="$(Protocol/scripts/get-flatc.sh "$repo_root/.tools")" ||
  fail "could not install the pinned flatc"
"$flatc" --version

xcode="/Applications/Xcode.app/Contents/Developer"
[[ -d "$xcode" ]] || fail "Xcode not found at $xcode"
# Xcode may not be the global developer directory, so it is set per command.
with_xcode() { DEVELOPER_DIR="$xcode" "$@"; }
# quiet <log-name> <command...>: runs a command, showing the end of its log only if it fails.
quiet() {
  local log="$work/$1.log"
  shift
  "$@" >"$log" 2>&1 || {
    tail -60 "$log"
    return 1
  }
}
# Fails unless the log reports at least one executed test, no failures and no skipped tests:
# a skipped test verifies nothing.
ran_tests() {
  local log="$work/$1.log" skipped summary
  skipped="$(grep -iE "^Test case '.*' skipped" "$log" || true)"
  [[ -z "$skipped" ]] || {
    echo "$skipped"
    fail "$1 skipped $(grep -c . <<<"$skipped") test(s); free what they need (see the reasons above) and run again"
  }
  # A run can have several test bundles, each with its own summaries, so check every line.
  summary="$(grep -E 'Executed [0-9]+ tests?, with ' "$log" || true)"
  [[ -n "$summary" ]] || fail "$1 has no test summary line"
  bad="$(grep -vE 'Executed [0-9]+ tests?, with 0 failures' <<<"$summary" || true)"
  [[ -z "$bad" ]] || fail "$1 skipped or failed tests: $(head -1 <<<"$bad")"
  passed="$(grep -ciE "^Test case '.*' passed" "$log" || true)"
  [[ "$passed" -ge 1 ]] || fail "$1 did not run any tests"
  echo "$passed tests passed"
}

step "vendored FlatBuffers runtime"
scripts/vendor-flatbuffers.sh "$work/runtime" >/dev/null ||
  fail "could not rebuild the vendored runtime"
diff -r -x .DS_Store "$work/runtime" Sources/CutawayFlatBuffers ||
  fail "Sources/CutawayFlatBuffers differs from upstream; run: scripts/vendor-flatbuffers.sh"
head -1 Sources/CutawayFlatBuffers/UPSTREAM

step "generated code"
scripts/generate-wire.sh "$work/generated" >/dev/null || fail "could not generate the wire code"
diff -r -x .DS_Store "$work/generated" Sources/CutawayWire/Generated ||
  fail "Sources/CutawayWire/Generated is out of date; run: scripts/generate-wire.sh"
echo "generated code matches the pinned schema"

step "module isolation"
if grep -rnE --include='*.swift' \
  '^[[:space:]]*(@testable[[:space:]]+)?([a-z]+[[:space:]]+)?import[[:space:]]+(FlatBuffers|Common)[[:space:]]*$|canImport\((FlatBuffers|Common)\)' \
  Sources Tests Demo; then
  fail "sources must not refer to the upstream module names FlatBuffers or Common"
fi
if grep -rnE --include='*.swift' 'import[[:space:]]+CutawayFlatBuffers' \
  Sources/CutawayServer Sources/cutaway-probe Tests/CutawayServerTests Tests/CutawayProbeTests Demo; then
  fail "only CutawayWire and its tests may import CutawayFlatBuffers"
fi
echo "no upstream module names; FlatBuffers stays inside CutawayWire"

step "S-REL-02: source format"
# Formatting may change whitespace and line breaks only, so .swiftformat may enable layout
# rules from this list and nothing else.
layout_rules="indent spaceAroundOperators spaceAroundParens spaceAroundBraces spaceAroundBrackets
  spaceAroundComments spaceAroundGenerics spaceInsideParens spaceInsideBrackets spaceInsideBraces
  spaceInsideGenerics spaceInsideComments consecutiveBlankLines trailingSpace blankLinesAtStartOfScope
  blankLinesAtEndOfScope blankLinesBetweenScopes blankLinesAroundMark linebreakAtEndOfFile linebreaks
  elseOnSameLine leadingDelimiters wrapAttributes wrapArguments wrap braces"
[[ "$(grep -cE '^--rules ' .swiftformat)" == 1 ]] || fail ".swiftformat must have exactly one --rules line"
if grep -qE '^--(enable|disable) ' .swiftformat; then
  fail ".swiftformat must list its rules in --rules only"
fi
enabled="$(awk '$1 == "--rules" { print $2 }' .swiftformat | tr ',' '\n')"
unexpected="$(grep -vxF -f <(tr -s ' \n' '\n' <<<"$layout_rules" | grep .) <<<"$enabled" || true)"
[[ -z "$unexpected" ]] ||
  fail ".swiftformat enables rules that are not layout-only: $(echo $unexpected)"
excluded="$(awk '$1 == "--exclude" { print $2 }' .swiftformat | tr ',' '\n')"
for path in Sources/CutawayFlatBuffers Sources/CutawayWire/Generated; do
  grep -qxF "$path" <<<"$excluded" || fail ".swiftformat must exclude $path (upstream and generated code)"
done
swiftformat="$(scripts/get-swiftformat.sh "$repo_root/.tools")" ||
  fail "could not install the pinned SwiftFormat"
quiet swiftformat "$swiftformat" --lint . ||
  fail "sources are not formatted; run: $swiftformat ."
echo "SwiftFormat $("$swiftformat" --version): $(tail -1 "$work/swiftformat.log")"

step "S-REL-04: SwiftLint"
for path in Sources/CutawayFlatBuffers Sources/CutawayWire/Generated; do
  grep -qxF "  - $path" .swiftlint.yml || fail ".swiftlint.yml must exclude $path (upstream and generated code)"
done
# Exceptions name the line they cover; a file-wide `swiftlint:disable` would hide later code too.
blanket="$(grep -rnE --include='*.swift' 'swiftlint:disable( |$)' Package.swift Sources Tests Demo scripts |
  grep -vE '^Sources/(CutawayFlatBuffers|CutawayWire/Generated)/' || true)"
[[ -z "$blanket" ]] || {
  head -5 <<<"$blanket"
  fail "use swiftlint:disable:next or :this for a single line, not swiftlint:disable"
}
swiftlint="$(scripts/get-swiftlint.sh "$repo_root/.tools")" || fail "could not install the pinned SwiftLint"
# SwiftLint needs SourceKit from Xcode. --strict makes warnings fail too.
quiet swiftlint with_xcode "$swiftlint" lint --strict --quiet ||
  fail "SwiftLint found violations (above)"
echo "SwiftLint $("$swiftlint" --version): no violations; exceptions: $(grep -rcE --include='*.swift' 'swiftlint:disable:(next|this)' Package.swift Sources Tests Demo scripts | awk -F: '{ n += $2 } END { print n + 0 }')"

step "S-API-03: no package dependencies"
with_xcode swift package dump-package >"$work/package.json" || fail "Package.swift does not load"
jq -e '.dependencies | length == 0' "$work/package.json" >/dev/null ||
  fail "Package.swift declares external dependencies"
echo "dependencies: none"

step "S-API-02: release trait"
jq -e '[.traits[] | select(.name == "ReleaseEnabled")] | length == 1' "$work/package.json" >/dev/null ||
  fail "Package.swift does not declare the trait ReleaseEnabled"
jq -e '[.traits[] | .enabledTraits[]?] | index("ReleaseEnabled") | not' "$work/package.json" >/dev/null ||
  fail "the trait ReleaseEnabled must not be enabled by default"
echo "trait ReleaseEnabled: declared, off by default"

step "swift build (macOS)"
quiet swift-build with_xcode swift build || fail "swift build"

step "swift test (macOS)"
quiet swift-test with_xcode swift test || fail "swift test"
ran_tests swift-test

step "S-API-03: compiles for iOS 13"
# Xcode 27's build system rejects deployment targets below 15.0 and silently raises the
# package's iOS 13 to 15.0, so this check drives the compiler directly: it type-checks
# every module against the iOS SDK with iOS 13 availability.
mkdir -p "$work/ios13"
ios13_swiftc=(xcrun --sdk iphoneos swiftc -target arm64-apple-ios13.0)
compile_for_ios13() { # <output-dir> <module> <swift-language-mode> [swiftc flags...]
  local out="$1" module="$2" mode="$3"
  shift 3
  find "Sources/$module" -name '*.swift' -print0 |
    with_xcode xargs -0 "${ios13_swiftc[@]}" "$@" \
      -swift-version "$mode" -parse-as-library -wmo \
      -module-name "$module" -I "$out" \
      -emit-module -emit-module-path "$out/$module.swiftmodule" \
      -emit-object -o "$out/$module.o"
}
# The library targets in dependency order, each with the language mode Package.swift gives it.
ios13_modules=("CutawayFlatBuffers 5" "CutawayWire 6" "CutawayServer 6")
declared="$(jq -r '. as $p | .targets[] | select(.type == "regular") |
  "\(.name) \([.settings[] | .kind.swiftLanguageMode._0 // empty][0] // $p.swiftLanguageVersions[0])"' \
  "$work/package.json" | sort)"
[[ "$declared" == "$(printf '%s\n' "${ios13_modules[@]}" | sort)" ]] ||
  fail "the library targets in Package.swift no longer match the list this step compiles for iOS 13; update ios13_modules in scripts/verify.sh. Package.swift declares: $(echo "$declared" | tr '\n' ',')"
# The check must have teeth: code that uses an iOS 15 API in a DEBUG block has to be rejected.
printf 'import UIKit\n#if DEBUG\nfunc canary() { _ = UIColor.tintColor }\n#endif\n' >"$work/ios13/canary.swift"
if with_xcode "${ios13_swiftc[@]}" -D DEBUG -typecheck "$work/ios13/canary.swift" >"$work/ios13-canary.log" 2>&1; then
  fail "the iOS 13 check accepted an iOS 15 API; it is not checking availability"
fi
grep -q "only available in iOS 15" "$work/ios13-canary.log" || {
  cat "$work/ios13-canary.log"
  fail "the iOS 13 canary failed for an unexpected reason"
}
# The server's real code is compiled when DEBUG or the package trait ReleaseEnabled is
# defined, and left out otherwise (S-API-02). All three variants have to compile.
for condition in DEBUG ReleaseEnabled none; do
  out="$work/ios13/$condition"
  mkdir -p "$out"
  flags=()
  [[ "$condition" == none ]] || flags=(-D "$condition")
  for entry in "${ios13_modules[@]}"; do
    module="${entry% *}"
    quiet "ios13-$condition-$module" compile_for_ios13 "$out" "$module" "${entry#* }" ${flags[@]+"${flags[@]}"} ||
      fail "$module does not compile for iOS 13 (condition: $condition)"
    minos="$(with_xcode xcrun vtool -show-build "$out/$module.o" | awk '$1 == "minos" { print $2; exit }')"
    [[ "$minos" == "13.0" ]] || fail "$module was compiled for iOS '$minos', expected 13.0"
  done
  with_xcode xcrun nm "$out/CutawayServer.o" >"$work/ios13/$condition.symbols"
  with_xcode xcrun nm "$out/CutawayWire.o" "$out/CutawayFlatBuffers.o" >"$work/ios13/$condition.wire-symbols"
done
echo "CutawayFlatBuffers, CutawayWire, CutawayServer: minos 13.0, with DEBUG, with ReleaseEnabled, with neither"
# S-API-02: the condition has to make a difference.
grep -q ServerController "$work/ios13/DEBUG.symbols" || fail "the DEBUG build does not contain the server"
grep -q ServerController "$work/ios13/ReleaseEnabled.symbols" ||
  fail "the ReleaseEnabled build does not contain the server"
# Without either condition the module may define nothing but its public entry point, the
# enum CutawayServer. Its symbols are mangled $s13CutawayServerAAO...; MXM is the module itself.
entry_point_only() { # <symbols-file>: prints the module's symbols that are not the entry point
  grep -F '$s13CutawayServer' "$1" | grep -vE '\$s13CutawayServer(AAO|MXM)' || true
}
extra="$(entry_point_only "$work/ios13/none.symbols")"
[[ -z "$extra" ]] || {
  head -5 <<<"$extra"
  fail "a build with neither DEBUG nor ReleaseEnabled contains more than the entry point; wrap the file in #if canImport(UIKit) && (DEBUG || ReleaseEnabled)"
}
echo "the server is compiled in with DEBUG or ReleaseEnabled, and left out otherwise"
# S-REL-01: the protocol's encoding code follows the same condition on platforms with UIKit.
# MXM is a module's own descriptor; a module with nothing in it may still have one.
wire_symbols() { # <symbols-file>: prints the symbols of CutawayWire and CutawayFlatBuffers
  grep -E '\$s(11CutawayWire|18CutawayFlatBuffers)' "$1" | grep -vE '\$s(11CutawayWire|18CutawayFlatBuffers)MXM' || true
}
for condition in DEBUG ReleaseEnabled; do
  grep -q '\$s11CutawayWire' "$work/ios13/$condition.wire-symbols" ||
    fail "the $condition build does not contain CutawayWire"
  grep -q '\$s18CutawayFlatBuffers' "$work/ios13/$condition.wire-symbols" ||
    fail "the $condition build does not contain CutawayFlatBuffers"
done
extra="$(wire_symbols "$work/ios13/none.wire-symbols")"
[[ -z "$extra" ]] || {
  head -5 <<<"$extra"
  fail "a build with neither DEBUG nor ReleaseEnabled contains CutawayWire or CutawayFlatBuffers; wrap the file in #if !canImport(UIKit) || DEBUG || ReleaseEnabled"
}
echo "CutawayWire and CutawayFlatBuffers are compiled in under the same conditions, and left out otherwise"

step "xcodebuild (iOS)"
quiet ios-build with_xcode xcodebuild build -scheme CutawayServer \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData/package ||
  fail "building CutawayServer for iOS"

command -v xcodegen >/dev/null || fail "xcodegen is not installed (brew install xcodegen)"

step "S-REL-01: release symbols"
# The demo app built in Release for devices, without and with the trait ReleaseEnabled. Without
# it the product may contain the entry point only: no listener and no internal server types.
quiet xcodegen xcodegen generate --spec Demo/project.yml || fail "xcodegen"
quiet xcodegen-release-enabled xcodegen generate --spec Demo/release-enabled.yml ||
  fail "xcodegen (release-enabled)"
for variant in release release-enabled; do
  project=Demo/CutawayDemo.xcodeproj
  [[ "$variant" == release ]] || project=Demo/CutawayDemoReleaseEnabled.xcodeproj
  quiet "$variant-device-build" with_xcode xcodebuild build -project "$project" -scheme CutawayDemo \
    -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "DerivedData/$variant" \
    CODE_SIGNING_ALLOWED=NO || fail "building the demo app in Release for devices ($variant)"
  binary="DerivedData/$variant/Build/Products/Release-iphoneos/CutawayDemo.app/CutawayDemo"
  [[ -f "$binary" ]] || fail "the demo app was not built at $binary"
  with_xcode xcrun nm "$binary" >"$work/$variant.symbols"
done
# Matches are captured before printing: with pipefail, `grep | head` fails when head exits early.
network="$(grep -E 'NWListener|\$s7Network' "$work/release.symbols" || true)"
[[ -z "$network" ]] || {
  head -5 <<<"$network"
  fail "the Release build without the trait contains Network symbols"
}
extra="$(entry_point_only "$work/release.symbols")"
[[ -z "$extra" ]] || {
  head -5 <<<"$extra"
  fail "the Release build without the trait contains internal server types"
}
grep -q NWListener "$work/release-enabled.symbols" ||
  fail "the Release build with the trait does not contain NWListener"
grep -qF '$s13CutawayServer0B10ControllerC' "$work/release-enabled.symbols" ||
  fail "the Release build with the trait does not contain the server"
# S-REL-01: the protocol's encoding code is left out with the server.
extra="$(wire_symbols "$work/release.symbols")"
[[ -z "$extra" ]] || {
  head -5 <<<"$extra"
  fail "the Release build without the trait contains CutawayWire or CutawayFlatBuffers"
}
grep -q '\$s11CutawayWire' "$work/release-enabled.symbols" ||
  fail "the Release build with the trait does not contain CutawayWire"
grep -q '\$s18CutawayFlatBuffers' "$work/release-enabled.symbols" ||
  fail "the Release build with the trait does not contain CutawayFlatBuffers"
echo "without the trait: the entry point only, no Network, CutawayWire or CutawayFlatBuffers symbols; with the trait: the server, NWListener and CutawayWire"

if [[ -n "$mac_only" ]]; then
  printf '\nverify: OK (mac-only; simulator steps skipped, this is not a full verification)\n'
  exit 0
fi

step "simulator tests"
udid="${CUTAWAY_SIMULATOR_UDID:-}"
if [[ -z "$udid" ]]; then
  udid="$(with_xcode xcrun simctl list devices available -j |
    jq -r '[.devices | to_entries[] | select(.key | contains("iOS")) | .value[] | select(.name | startswith("iPhone"))][0].udid // empty')"
fi
[[ -n "$udid" ]] || fail "no available iPhone simulator; set CUTAWAY_SIMULATOR_UDID"
echo "simulator $udid"
quiet xcodegen xcodegen generate --spec Demo/project.yml || fail "xcodegen"
demo_bundle_id="dev.cutaway.demo"
# A demo app left running would hold a port of the range the tests use.
with_xcode xcrun simctl terminate "$udid" "$demo_bundle_id" >/dev/null 2>&1 || true
quiet demo-test with_xcode xcodebuild test -project Demo/CutawayDemo.xcodeproj -scheme TestHost \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath DerivedData/demo ||
  fail "simulator tests"
ran_tests demo-test
quiet demo-build with_xcode xcodebuild build -project Demo/CutawayDemo.xcodeproj -scheme CutawayDemo \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath DerivedData/demo ||
  fail "building the demo app"

step "S-API-02: release build"
# The same public-API test bundle, built in Release, twice: without the trait the server
# must not listen; with the trait it must.
quiet release-test with_xcode xcodebuild test -project Demo/CutawayDemo.xcodeproj -scheme TestHostRelease \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath DerivedData/demo ||
  fail "Release build without the trait: the server must not listen"
ran_tests release-test
quiet xcodegen-release-enabled xcodegen generate --spec Demo/release-enabled.yml ||
  fail "xcodegen (release-enabled)"
quiet release-enabled-test with_xcode xcodebuild test -project Demo/CutawayDemoReleaseEnabled.xcodeproj \
  -scheme TestHostRelease -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath DerivedData/demo-release-enabled ||
  fail "Release build with the trait ReleaseEnabled: the server must listen"
ran_tests release-enabled-test

step "probe"
demo_app="DerivedData/demo/Build/Products/Debug-iphonesimulator/CutawayDemo.app"
[[ -d "$demo_app" ]] || fail "the demo app was not built at $demo_app"
quiet probe-build with_xcode swift build --product cutaway-probe || fail "building cutaway-probe"
probe="$(with_xcode swift build --show-bin-path)/cutaway-probe"
with_xcode xcrun simctl bootstatus "$udid" -b >/dev/null || fail "could not boot the simulator"
with_xcode xcrun simctl install "$udid" "$demo_app" || fail "installing the demo app"
with_xcode xcrun simctl launch "$udid" "$demo_bundle_id" >/dev/null || fail "launching the demo app"
"$probe" --bundle-id "$demo_bundle_id" --wait 30 --require-icon --expect-demo || {
  with_xcode xcrun simctl terminate "$udid" "$demo_bundle_id" >/dev/null 2>&1 || true
  fail "cutaway-probe against the demo app"
}
with_xcode xcrun simctl terminate "$udid" "$demo_bundle_id" >/dev/null || fail "terminating the demo app"
# A probe that finds no server must fail: one that checks nothing must not look like a pass.
absent=""
for _ in 1 2 3 4 5; do
  if "$probe" --bundle-id "$demo_bundle_id" >"$work/probe-absent.log" 2>&1; then
    sleep 1 # The app's port may take a moment to close.
  else
    absent=yes
    break
  fi
done
[[ -n "$absent" ]] || fail "cutaway-probe passed although the demo app is not running"
grep -q "no server" "$work/probe-absent.log" || {
  cat "$work/probe-absent.log"
  fail "cutaway-probe failed for an unexpected reason"
}
echo "without the app: $(cat "$work/probe-absent.log")"

printf '\nverify: OK\n'
