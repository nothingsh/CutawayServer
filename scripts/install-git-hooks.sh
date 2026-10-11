#!/bin/bash
# Points git at the repository's hooks in .githooks/ (the pre-commit hook formats and lints the
# staged Swift files). Run once per clone; it changes only this clone's .git/config.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git -C "$repo_root" config core.hooksPath .githooks
echo "core.hooksPath = $(git -C "$repo_root" config core.hooksPath)"
