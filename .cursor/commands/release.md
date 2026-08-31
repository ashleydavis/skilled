---
description: Cut the next patch release. Push the current branch if needed, tag vX.Y.Z, push the tag, and wait until the Release workflow publishes the GitHub Release.
disable-model-invocation: true
argument-hint: "[vX.Y.Z]"
---

# Release

Cut a GitHub Release for this repo. Do the work; do not only describe it. Do not invent a version, skip a step, or force-push. Pre-flight checks (dirty tree, wrong branch, behind origin) still stop. After a tag is pushed, a failed workflow is not the end: diagnose, fix, and keep going until the GitHub Release exists.

Arguments: `$ARGUMENTS` is an optional explicit version (`v0.0.6` or `0.0.6`). If omitted, bump the patch of the highest existing `vMAJOR.MINOR.PATCH` tag.

## Current state

```
!`git status -sb`
```

```
!`git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -8`
```

```
!`gh release list --limit 5`
```

## Rules

- Never `git config`. Never `--force` / `--force-with-lease`. Never `--no-verify`. Never delete or move a tag that already exists on origin.
- Never rewrite `src/lib/version.zig`. The Release workflow overwrites it from the tag at build time. The working-copy string stays `0.0.1` on purpose.
- The workflow file is `.github/workflows/release.yml` (`name: Release`). A push of a tag matching `v*.*.*` starts it. `workflow_dispatch` publishes a pre-release; do not use that here.
- Use `gh` against `origin`. Do not hardcode an owner or repo name.

## Procedure

1. **Working tree.** `git status`. Stop if any tracked file is modified or staged. Untracked files that are not this release are also a stop if they would be easy to leave out of the tagged commit by accident.

2. **Branch.** `git fetch origin --tags`. The current branch must be the repository default branch (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`) and must track `origin`. Stop if HEAD is behind origin (do not pull). If HEAD is ahead of origin, `git push` that branch (no extra flags). After that, `git status -sb` must show in sync with `origin/<default>`.

3. **Next version.** Fetch tags again if the fetch in step 2 is stale. Read the highest tag that matches `vMAJOR.MINOR.PATCH` with three non-negative integers and no suffix (`git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname`). Compare with `gh release list` so a release that exists only on GitHub still counts.
   - If `$ARGUMENTS` is set: normalize to `vMAJOR.MINOR.PATCH`. Stop if it is not that shape, or if that tag or release already exists.
   - If `$ARGUMENTS` is empty: if no such tag exists, the next tag is `v` plus the string in `src/lib/version.zig`. Otherwise increment PATCH on the highest tag (`v0.0.5` → `v0.0.6`).
   - Stop if that tag already exists locally or on origin (`git ls-remote --tags origin 'refs/tags/v…'`).
   - Tell the human the version you will tag and continue.

4. **Tag.** Annotated tag on the current HEAD only: `git tag -a "vX.Y.Z" -m "skl vX.Y.Z"`. Do not tag a different commit.

5. **Push the tag.** `git push origin "vX.Y.Z"`. That push is what starts the Release workflow.

6. **Watch the workflow.** Poll until a run of workflow `Release` appears for this tag (`gh run list --workflow=Release --json databaseId,headBranch,status,conclusion,url,event,displayTitle,createdAt --limit 10`). `headBranch` for a tag push is the tag name. Then `gh run watch <id> --exit-status`. The job graph is `prepare` → `build` (linux/mac/win matrix) → `smoke-tests` (native runners per binary) → `create-release`. Do not declare success from a still-running run. If the run fails, `gh run view <id> --log-failed`, fix the cause in this checkout, commit and push on the default branch, then tag the **next** patch (do not delete or move the failed tag) and watch that run. Repeat until a GitHub Release exists.

7. **Confirm the release.** `gh release view` the tag that actually published `--json tagName,isDraft,isPrerelease,url,assets`. Success means it exists, is not a draft, is not a prerelease, and has the four artifacts `skl-linux-x64.tar.gz`, `skl-windows-x64.zip`, `skl-macos-x64.tar.gz`, `skl-macos-arm64.tar.gz`. Print the release URL. That is the end of the command.
