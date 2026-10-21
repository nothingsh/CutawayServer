# Contributing to CutawayServer

Thanks for helping. This page says how to build and check the code, where changes go and how they
are reviewed. The [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) page on
the Cutaway website explains how the three repositories fit together.

## Build and check

After cloning, run `./setup.sh` once. It checks out the protocol submodule, checks for Xcode,
installs XcodeGen and jq with Homebrew if they are missing, installs the pinned tools into
`.tools/`, sets up the git hooks and generates the demo Xcode projects. Running it again is
harmless.

| Task | Command |
|---|---|
| Run every check (needs an iPhone simulator) | `scripts/verify.sh` |
| Run the checks that need no simulator, as CI does | `scripts/verify.sh --mac-only` |
| Format | `"$(scripts/get-swiftformat.sh)" .` |
| Lint | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$(scripts/get-swiftlint.sh)" lint --strict` |
| Check a running server | `swift run cutaway-probe --bundle-id dev.cutaway.demo --wait 30` |

- The pre-commit hook formats the staged Swift files, stages the result and lints them; a commit
  with lint violations is rejected. Xcode does not show SwiftLint's findings, so the hook and
  `scripts/verify.sh` are where they surface.
- `cutaway-probe` connects to a running server, performs the handshake, fetches the icon, the
  hierarchy, and the images and attributes of every layer, and checks every frame it receives.
  Against the demo app, `--expect-demo` also checks known content, colors and attribute values.
  `--slow-read 200` reads like a slow client to confirm that the server completes the stream under
  backpressure.
- The test suite enforces the performance limits on every run; the measured values are on the
  website's [Performance](https://nothingsh.github.io/Cutaway/resources/performance) page.

## Branches

- `main` holds released versions only. Every release is a tag on `main`.
- Work happens on `dev-<next version>`, for example `dev-1.1.0`. There is one such branch at a
  time: the `dev-*` branch in the branch list.
- Open pull requests against that `dev-*` branch. Pull requests into `main` are closed
  automatically.
- When a version is ready, the maintainer rebases the `dev-*` branch onto `main`, tags the release
  and starts the next `dev-*` branch from `main`. A pull request still open at that point needs to
  be retargeted to the new branch.

## Issues and planning

- Report bugs and suggest features with the issue templates.
- Each version is a milestone. An issue in a milestone is planned for that version; an issue
  without one is not scheduled yet.
- Features that need new messages or fields also need a change to the
  [Cutaway protocol](https://github.com/nothingsh/CutawayProtocol). The `protocol` label marks
  them; the change is proposed in that repository first.
- For anything larger than a small fix, comment on the issue before you start, so the approach
  can be agreed first.

## Pull requests

- Branch from the current `dev-*` branch and keep one change per pull request. Link the issue it
  closes, e.g. "Closes #12".
- Use a [Conventional Commits](https://www.conventionalcommits.org/) prefix in the title, e.g.
  `feat: ...`, `fix: ...`, `docs: ...`.
- The `verify` check must pass, and the maintainer reviews every change.
- History is linear: pull requests are merged by squash or rebase. To pick up new commits on the
  `dev-*` branch, rebase onto it rather than merging it in.
- Do not consult the source code of other view-inspection tools while working on this one.
