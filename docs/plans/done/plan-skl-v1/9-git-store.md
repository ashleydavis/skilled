# 9. Git store (clone/fetch via subprocess)

## Goal

Wrap `git` on `PATH` with argv-array spawns (never a shell) so packages can be cloned and fast-forwarded in the store.

## Files

- `src/lib/git.zig` + `src/lib/git.test.zig`
- Re-export from `src/lib/lib.zig`. Wire `test { _ = @import("git.test.zig"); }`.

## Spawn rules

Every spawn is `std.process.run` with an **argv array** and `environ_map` — never a shell, never interpolated into `sh -c`. Pass `io: std.Io`.

Expose a `GitRunner` (function pointer or struct of callbacks) so tests inject a fake runner and do not hit the network.

## Operations

- `clone(io, environ, url, dest)` runs `git clone -- <url> <dest>` (create parent dirs first).
- `showFile(io, environ, repo, ref, path)` runs `git show -- <ref>:<path>` and returns stdout (used by `init --from` and `add --from` in step 12, not by package install).
- `fetchUpdate(io, environ, dest)`:
  1. If `git rev-parse --abbrev-ref HEAD` is `HEAD`, error (detached).
  2. If `git status --porcelain` is non-empty, error (dirty); do not merge.
  3. If `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}` fails, error (no upstream).
  4. `git fetch`.
  5. `git merge --ff-only @{upstream}`. Non-fast-forward (diverged) is an error; do not reset, do not pull.
- `headSha(io, environ, dest)` via `git rev-parse HEAD`.

`git` not on PATH maps to a readable error.

## Tests

Fake runner only — no network:

- Clone argv uses `--`; dest path is `store/host/owner/repo`.
- `showFile` argv is `git show -- <ref>:<path>`.
- `fetchUpdate` refuses dirty / detached / missing upstream.
- ff-only merge argv.
- `headSha` argv.
- `git` not on PATH maps to a readable error.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Added `src/lib/git.zig` (with co-located tests) and re-exported it from `lib.zig`.

- `GitRunner` is `.process` (CLI, `std.process.run` with an argv array and `environ_map`) or `.custom` (tests). Never a shell. `io` is threaded through every spawn.
- `clone` creates dest's parent directories, then `git clone -- <url> <dest>`. `showFile` is `git show -- <ref>:<path>` and returns stdout untrimmed. `headSha` is `git rev-parse HEAD` with whitespace stripped.
- `fetchUpdate` refuses detached HEAD, a dirty tree, and missing `@{upstream}` before `git fetch` and `git merge --ff-only @{upstream}`. Non-fast-forward is an error; no reset or pull.
- `FileNotFound` from spawn maps to a readable "git is not on PATH" failure. Tests inject a scripted runner and do not hit the network.
- Each spawn uses a copy of `environ` with `GIT_DIR` and `GIT_WORK_TREE` removed so dest/cwd is the repo git uses (hooks, worktrees, GitHub Actions checkout). The rest of the map is kept (`SSH_AUTH_SOCK`, `GIT_CONFIG_*`). The caller's map is not mutated.
- Public functions take `allocator`, `runner`, and `fail` in addition to the abbreviated plan signatures, matching `package.scan`.
- Not wired into `main` yet (CLI is step 11). Smoke tests are step 13; not run. `zig build` and `zig build test` pass; the test count moved when `git.test.zig` was added.
