# 6. Git remote parsing (SSH only) and name validation

## Goal

Parse SSH-only clone specs into host/owner/repo, reject HTTPS and filesystem paths, and validate names so store paths and `skills/<ns>` cannot escape agent roots.

## Files

- `src/lib/remote.zig` + `src/lib/remote.test.zig`
- Re-export from `src/lib/lib.zig`. Wire `test { _ = @import("remote.test.zig"); }`.

## Accept

- `owner/repo` → clone URL `git@github.com:owner/repo.git`, host `github.com`, owner, repo.
- `git@host:owner/repo.git` or `git@host:owner/repo` → use as-is; host/owner/repo parsed from it.

Repo name (package name) is the git repo name without `.git`.

## Reject

HTTPS, `github:owner/repo`, and local filesystem paths, with a clear error.

## Validate

`host` labels, `owner`, `repo`, and (used by later steps) `namespace` with the same rule:

- Non-empty, not `.` or `..`
- No `/`, `\`, or `:`
- No Windows-illegal characters `<>"|?*`
- Each segment matches `[A-Za-z0-9._-]+`

Host may contain dots (`github.example.com`) but each label is validated; `..` in a host is rejected. Invalid names error before any clone, symlink, or URL is built. This is what stops `skills/<ns>` from escaping agent roots.

Never inspect `~/.ssh` or private key files. Git performs SSH authentication.

## Tests

- Parse success: `owner/repo`, SSH URL; package name strips `.git`.
- Parse fail: https, filesystem path.
- Reject `..` / `/` / `:` / empty / Windows-illegal names.
- Store path mapping `git@github.example.com:acme/skills.git` → `.../store/github.example.com/acme/skills`.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Added `src/lib/remote.zig` (with co-located tests) and re-exported it from `lib.zig`.

- `parse` accepts `owner/repo` (clone URL `git@github.com:owner/repo.git`) and `git@host:owner/repo[.git]` (clone URL kept as-is). HTTPS, `github:`, and filesystem paths fail with a `Failure` message. Nothing inspects `~/.ssh`.
- `Remote` is `clone_url` plus the three store segments (`host`, `owner`, `repo`). `repo` is the package name with `.git` stripped. `clone_url` is stored so an SSH spec that omitted `.git` is still passed to git unchanged; host/owner/repo alone cannot recover that.
- `validateName` is pub (tests and later `--ns` / link steps) and is the one rule for owner, repo, namespace, and each host label: non-empty, not `.`/`..`, `[A-Za-z0-9._-]+`. Dotted hosts like `github.example.com` are split into labels; `..` in a host is rejected.
- Store mapping is parse then `paths.clonePath`: `git@github.example.com:acme/skills.git` → `.../store/github.example.com/acme/skills`.

Not wired into `main` yet (CLI is step 11). Smoke tests are step 13; not run. `zig build` and `zig build test` pass; the test count moved when `remote.test.zig` was added.
