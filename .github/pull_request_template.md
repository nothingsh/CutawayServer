<!--
Title: use a Conventional Commits prefix, e.g. "feat: ...", "fix: ...", "docs: ...".
The title becomes the commit subject on main.
-->

## Summary

<!-- What does this change and why? Link the issue it closes, e.g. "Closes #123". -->

## Verification

- [ ] `scripts/verify.sh` passes locally, including the simulator steps (CI runs only `--mac-only`).
- [ ] New or changed behavior has tests.

<details>
<summary>Output of <code>scripts/verify.sh</code></summary>

```
Paste the last lines of the output here.
```

</details>

## Checklist

- [ ] This change does not modify `Protocol/`. Protocol changes go to the CutawayProtocol repository.
- [ ] This change adds no third-party dependency and no Objective-C target.
- [ ] If this change touches `scripts/verify.sh`, `.gitmodules` or the pinned tool versions, the
      reason is explained above.
- [ ] I wrote this code without consulting the source code of other view-inspection tools.
