# 11. Wire CLI commands

## Goal

Wire `skl` subcommands through Commander in `src/main.zig`, with each command in `src/cmd/`. `--from` on `init` and `add` is stubbed or refused until step 12; everything else in this step is real.

## Files

- `src/main.zig` — Commander program, context, dispatch.
- `src/cmd/init.zig`, `install.zig`, `add.zig`, `remove.zig`, `update.zig`, `list.zig`, `docs.zig`
- Matching `src/cmd/*.test.zig` for each.
- **Each `src/cmd/*.zig` ends with `test { _ = @import("….test.zig"); }`.**
- `src/main.zig` imports every cmd module so the exe test step actually runs those blocks (step 2 only wired lib + exe; without the cmd imports the cmd tests never run).

## Context

Holds allocator, `io: std.Io`, `environ`, cwd, home, style, non_interactive, global flag. `main(init: std.process.Init)` builds that from the process.

Global options on the root command: `--global` / `-g`, `--no-color`, `--non-interactive` / `-n`, `--version` / `-V`. `skl help` is the same as `--help` / `-h`. `skl version` is the same as `--version` / `-V`. Bare `skl` (no args) prints help and exits **0** (`Displayed`). `help` and `version` do not require `skl.yaml`.

Command-specific: `--ns <namespace>` on `add`, `--from <spec>` on `init` and `add` (implemented in step 12), `--open` on `docs`. `add` declares optional `[repo]`.

Each command function takes explicit `io`, paths, and runners so tests inject temp dirs and fake git.

## Missing `skl.yaml`

`install`, `add`, `remove`, `update`, `list`, and `docs` error (exit 1) with `no skl.yaml; run skl init`. `init` is what creates it.

## Commands

- `skl init` — write `skl.yaml` with `packages: []` if missing. `-g` selects global config path. Refuse to wipe a file that already lists packages. Stow-safe write. `--from` is step 12; until then, `--from` may be declared and error with a clear not-implemented message, or parse-and-refuse — do not clone.
- `skl install` / `skl i` — read active `skl.yaml`, clone/update every package into the store, link each namespace into that scope’s Cursor and Claude dirs. Progress on stderr. Idempotent. On partial failure (package *k* of *N* fails): stop, exit 1, **keep** packages 1..*k-1* already cloned/linked (no rollback), print which package failed. Next `install` continues the rest.
- `skl add <repo>` — require `--ns <namespace>` (validated as in step 6). If `--ns` omitted: prompt on TTY when interactive; **error** (exit 1, no hang) when non-interactive. Reject if namespace already in this `skl.yaml`. **Clone + `scan` first**, then append YAML (stow-safe) and link. If clone or scan fails, do **not** write a YAML entry. A successful clone of an invalid package (no `skills/` and no `commands/`) may leave a store clone (same as `remove` leaving the store); YAML is unchanged. If the clone fails, there is no store dest. `--from` on `add` is step 12; until then, declare it and refuse — do not clone.
- `skl remove <query>` — match using the rules below; unlink namespace; remove that one YAML entry. Leave store clone.
- `skl update [repo]` — `fetchUpdate` in store for one package or all in the active YAML. Store-dir symlinks already show new files after a fast-forward; still call `linkPackage` (idempotent no-op if links are correct) so a missing link is repaired. Print `name  oldsha → newsha` or unchanged. Dirty / detached / diverged / no-upstream: exit 1 for that package with the `fetchUpdate` error; do not reset.
- `skl list` — print each package (name, namespace, repo, description) and each skill/command using the logical id `ns:name` (nested command `commands/plan/create.md` under namespace `cmd` is `cmd:plan/create`). Colors/icons when enabled. Missing store clone: still print the YAML row; item list is empty with a note that it is not installed.
- `skl docs [package]` — **no HTTP.** There is no Pages probe, no HEAD/GET, no HTTP client. If no args and interactive: menu of packages, Enter selects. Always print package details (from YAML + scan if the store clone exists; if the clone is missing, print YAML fields and skip item descriptions — `--open` still works). Print a GitHub Pages **guess** (`https://<owner>.github.io/<repo>/`) as text only, never fetch it. If `--open`: skip prompt and open a browser to the **git repo HTTPS URL** (see URL rules below). Else if interactive: ask whether to open that same repo URL. Non-interactive without a package name: error.

## Browser spawn

Never a shell. If env `SKL_BROWSER` is set to a non-empty path, spawn argv `{ SKL_BROWSER, url }`. Else: Linux `xdg-open`, macOS `open`, Windows argv `{ "cmd.exe", "/C", "start", "", url }` (empty title argument so `start` does not eat the URL). `std.process.run` with that argv and `io`.

## Repo URL for `--open`

Built only after owner/repo/host pass step 6 validation. `owner/repo` or `git@github.com:…` → `https://github.com/<owner>/<repo>`. Other SSH hosts → `https://<host>/<owner>/<repo>`. Never interpolate unsanitised strings into a URL.

## `remove` matching

Compare the query, in order, against each YAML entry:

1. Exact `repo` field string.
2. Canonical SSH URL for that entry.
3. `owner/repo` shorthand.
4. Repo name (last path segment, `.git` stripped).
5. Namespace.

If exactly one entry matches, remove it. If more than one matches (same repo under two namespaces, or query equals both a name and a different entry's namespace), error listing the matches and tell the user to pass a unique `owner/repo` or the namespace. `skl remove nosuch` exits non-zero. There is no `--ns` flag on remove; namespace match is by the query string.

## Tests

Each command function is unit-tested with temp dirs and fake git:

- `cmd/init`: creates YAML; refuse wipe of a file that already lists packages; missing-config is not an error for init.
- `cmd/add`: requires ns when non-interactive; duplicate ns error; clone-then-YAML (failed scan leaves YAML unchanged); invalid namespace rejected.
- `cmd/install`: links all packages in fixture YAML; missing config errors; partial failure keeps earlier packages.
- `cmd/remove`: unlinks and drops YAML entry; match by repo string, name, SSH, namespace; ambiguous match errors.
- `cmd/update`: unchanged SHA vs changed SHA; dirty tree errors.
- `cmd/list`: formats package + items as `ns:name` (nested command `cmd:plan/create`); missing config; missing store clone still prints YAML row.
- `cmd/docs`: `--open` calls opener with **repo** URL; `SKL_BROWSER` argv; menu skipped when non-interactive without name; missing clone still allows `--open`; no HTTP client in the module.

Interactive-only behaviour (TTY menu, `--ns` prompt, docs “open?” prompt, spinner) is unit-tested with fake TTY flags, not smoke.

Confirm the test count moved for each new `*.test.zig`.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Wired Commander in `src/main.zig` and split commands into `src/cmd/` with co-located tests. `src/main.zig` imports every cmd module so the exe test step runs those blocks.

- Context (`src/cmd/context.zig`) holds allocator, `io`, environ, cwd, home, style, non_interactive, git/browser runners, and stdin/stdout/stderr. Each command's `run` takes that plus an `Args` struct (flags and positionals), so tests inject a `TemporaryDir` and `FakeGit` and never read the process.
- Shared helpers (`src/cmd/shared.zig`): missing-config wording `no skl.yaml; run skl init`, store resolve, clone-if-missing, package match (repo string, canonical SSH, `owner/repo`, name, namespace; ambiguous matches list the hits), HTTPS repo URL and Pages guess (text only), `SKL_BROWSER` / platform opener argv (Windows `cmd.exe /C start "" url`).
- `init` writes `packages: []` when missing; leaves an existing file (empty or already listing packages) un-wiped. `-g` selects the global path. `--from` is declared and refused (no clone) until step 12.
- `add` requires `--ns` (prompt when interactive; error naming `--ns` when not). Validates namespace, rejects duplicates, clone+scan first, then stow-safe YAML append and link. Failed scan leaves YAML unchanged. `--from` refused.
- `install` / `i` clones missing dests, scans, links. Partial failure keeps earlier packages and names the one that failed. Idempotent; does not fetch (that is `update`).
- `remove` unlinks then drops that YAML row; store clone stays. `update` `fetchUpdate` + idempotent `linkPackage`; prints unchanged or old SHA → new SHA; dirty/detached/diverged/no-upstream is an error. `list` prints YAML + `ns:name` items; missing clone still prints the row with “not installed”. `docs` has no HTTP; `--open` opens the git repo URL; non-interactive without a name errors; missing clone still allows `--open`.
- Test harness (`src/cmd/harness.zig`) materializes fixture packages on fake clone. Interactive `--ns` / docs menu / open-prompt covered with scripted stdin. `zig build` and `zig build test` pass; the test count moved when each `src/cmd/*.test.zig` was added. Smoke tests are step 13; not run.
