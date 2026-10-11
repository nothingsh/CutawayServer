#!/bin/bash
# Sets up a fresh clone for development, in one go. Safe to run again.
#
#   1. checks out the protocol submodule (Protocol/);
#   2. checks for Xcode, and installs XcodeGen and jq with Homebrew when they are missing;
#   3. installs the pinned flatc, SwiftFormat and SwiftLint into .tools/;
#   4. points git at the repository's hooks (.githooks/: format and lint on commit);
#   5. generates the demo Xcode projects (Demo/*.xcodeproj).
#
# It changes nothing outside this clone except what Homebrew installs, and leaves the global
# developer directory (xcode-select) alone.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

xcode="/Applications/Xcode.app/Contents/Developer"

step() { printf '\n== %s\n' "$1"; }
fail() {
  echo "setup: FAILED: $1" >&2
  exit 1
}

step "protocol submodule"
git submodule update --init --recursive || fail "could not check out Protocol/"
# scripts/verify.sh checks that Protocol/ is at a released tag on the protocol's main branch.
git -C Protocol fetch --quiet --tags origin main:refs/remotes/origin/main ||
  fail "could not fetch the protocol repository's tags and main branch"
echo "Protocol/ at $(git -C Protocol describe --tags --always)"

step "Xcode"
[[ -d "$xcode" ]] || fail "Xcode not found at /Applications/Xcode.app; install it from the App Store or developer.apple.com"
DEVELOPER_DIR="$xcode" xcodebuild -version | head -1
# Commands that need Xcode set DEVELOPER_DIR themselves; the global setting is not changed.

step "XcodeGen and jq"
missing=()
command -v xcodegen >/dev/null || missing+=(xcodegen)
command -v jq >/dev/null || missing+=(jq)
if [[ ${#missing[@]} -gt 0 ]]; then
  command -v brew >/dev/null ||
    fail "${missing[*]} not installed and Homebrew not found; install them (https://brew.sh), then run setup.sh again"
  echo "installing with Homebrew: ${missing[*]}"
  brew install "${missing[@]}" || fail "brew install ${missing[*]}"
fi
echo "xcodegen $(xcodegen --version | awk '{ print $NF }'), $(jq --version)"

step "pinned tools"
flatc="$(Protocol/scripts/get-flatc.sh "$repo_root/.tools")" || fail "could not install the pinned flatc"
swiftformat="$(scripts/get-swiftformat.sh "$repo_root/.tools")" || fail "could not install the pinned SwiftFormat"
swiftlint="$(scripts/get-swiftlint.sh "$repo_root/.tools")" || fail "could not install the pinned SwiftLint"
echo "$("$flatc" --version), SwiftFormat $("$swiftformat" --version), SwiftLint $("$swiftlint" --version)"

step "git hooks"
scripts/install-git-hooks.sh || fail "could not install the git hooks"

step "demo projects"
xcodegen generate --quiet --spec Demo/project.yml || fail "xcodegen (Demo/project.yml)"
xcodegen generate --quiet --spec Demo/release-enabled.yml || fail "xcodegen (Demo/release-enabled.yml)"
echo "Demo/CutawayDemo.xcodeproj, Demo/CutawayDemoReleaseEnabled.xcodeproj"

simulator="$(DEVELOPER_DIR="$xcode" xcrun simctl list devices available -j |
  jq -r '[.devices | to_entries[] | select(.key | contains("iOS")) | .value[] | select(.name | startswith("iPhone"))][0].name // empty')"
[[ -n "$simulator" ]] ||
  echo "note: no iPhone simulator is available; scripts/verify.sh needs one (Xcode > Settings > Components)"

printf '\nsetup: OK\n'
cat <<'EOF'

Next:
  scripts/verify.sh              the acceptance check (needs an iPhone simulator)
  scripts/verify.sh --mac-only   the steps that need no simulator
  open Demo/CutawayDemo.xcodeproj
EOF
