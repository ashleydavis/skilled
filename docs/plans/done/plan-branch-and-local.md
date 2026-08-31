# Branch and local package sources

## Overview

`skl` currently clones every package from its SSH remote onto the default branch and always links agent directories at the store clone. This plan adds two optional sources: a named git branch, and a local working tree. `skl add` is how a single package is installed, so `--branch` and `--local` are added there; `skl update` uses the same flags to switch an already-listed package; `skl install` (and `init --from`) honor the resulting YAML. Branch and local are persisted on the YAML row so a later `install` does the same thing. `--local` points agent symlinks at the working tree (live edits); `update --branch` clears `local`, checks the store clone out onto that branch, and relinks to the store.

Done. Step 11 (publish a `dev` branch on `ashleydavis/skl-example-skills`) was skipped: that repo stays on `main` only. README `--branch` examples use generic `owner/repo --branch feature`. Smoke tests still use a throwaway fixture `dev` branch on `acme/skills`.

## Issues

## Steps

1. **Write documentation, then STOP.** Draft the intended behaviour in the product docs so a human can review it before any Zig is written. Do not start later steps until the human approves. If the human revises the docs, revise the remaining plan steps to match before continuing.

   Update these files (describe durable behaviour; no test counts or other snapshot numbers):

   - `docs/COMMANDS.md`
     - Command table: `add` clones from `--branch` when given, or links a `--local` path; `update` takes the same flags to switch a listed package.
     - New subsection **`--branch` and `--local`**:
       - `skl add <repo> --ns <ns> --branch <name>` clones that branch into the store, writes `branch:` on the YAML row, and links from the store.
       - `skl add <repo> --ns <ns> --local <path>` does not clone. It scans `<path>`, writes an **absolute** `local:` on the YAML row, and links agent dirs at that path. `<repo>` is still required (identity for later `update --branch`).
       - `skl update <query> --branch <name>` requires a package query. Clears `local`, sets `branch`, clones the store dest if missing, checks that branch out with upstream tracking, relinks to the store.
       - `skl update <query> --local <path>` requires a package query. Sets `local` to the resolved absolute path, clears `branch`, relinks to that path. The store clone is left in place.
       - `skl update` with neither flag: if the row has `local:`, repair links at that path (no fetch). Otherwise existing fast-forward of the store clone.
       - `--branch` and `--local` are mutually exclusive on one invocation. They are not valid with `add --from`. `update --branch` / `--local` without a package query is an error.
       - `skl install` has no package argument and does not take these flags; it applies each row’s `branch` / `local`.
     - Flags table: add `--branch <name>` and `--local <path>`.
   - `docs/HOW_IT_WORKS.md`
     - YAML example showing optional `branch:` and `local:` (generic `acme` names). Omit a field when it is unset.
     - A row may have `branch` or `local`, not both. `repo` and `namespace` stay required.
     - Store layer is unchanged (`~/.skilled/store/<host>/<owner>/<repo>/`). `--local` does not replace the store path; it is the directory `linkPackage` receives.
     - Install of a `branch:` row: clone with `--branch` when dest is missing; if dest exists, check that branch out. Install of a `local:` row: do not clone; scan and link the local path (error if the path is missing or not a valid package).
   - `README.md`
     - `--branch` examples stay generic (`skl add owner/repo --ns demo --branch feature`). Do not put `--branch` on `ashleydavis/skl-example-skills` (that repo has no extra branch).
     - `--local` examples may still clone that public repo to a local path.
     - Keep existing default-branch examples as they are.
   - `src/main.zig` `HELP_EXAMPLES`: add one `add … --branch` line and one `update … --local` / `update … --branch` pair.

   After those doc edits: **STOP. Do not continue.** Wait for the human to review and approve. Incorporate any doc revisions into later steps before writing code.

2. **YAML schema: optional `branch` and `local`.** In `src/lib/config.zig`, extend `Package` with `branch: ?[]const u8 = null` and `local: ?[]const u8 = null` (each field commented). In `parsePackage`, read them with a new `readOptionalString` that returns null when the key is absent or YAML null, errors on empty string or a non-string. After both are read, if both are non-null, `fail.set` that a package cannot have both `branch` and `local`. `stringify` writes `repo`, then `namespace`, then `branch` only when set, then `local` when set, so existing two-field documents stay byte-identical. Unknown extra keys stay ignored. `src/lib/lib.zig` comment for config still names `{repo, namespace}` plus the optional fields. `src/lib/from.zig` `mergePackages` copies incoming `branch`/`local` as-is when appending; skip-same-package still compares repo identity only (does not overwrite an existing row’s branch/local).

   Compile (`zig build`) and `zig build test` before marking this step complete.

3. **Branch name rule.** In `src/lib/remote.zig`, add `pub fn validateBranch(name: []const u8, fail: *Failure)`. Reject empty, `HEAD` (any ASCII case), leading `-`, `\\`, `:`, and Windows-illegal `<>"|?*`. Allow `/` by splitting on `/` and calling `validateName` on each non-empty segment (so `feature/foo` works, `..` and `.` still fail). Leading/trailing `/` and empty segments (`a//b`) error. Used by `--branch` and by `git.clone` / `git.checkoutBranch` so a dash-prefixed name cannot become a git flag. `from.zig` blob refs keep using `validateName` (unchanged).

   Compile and `zig build test` before marking complete.

4. **Git: clone a branch, check a branch out.** In `src/lib/git.zig`:
   - Change `clone` to take `branch: ?[]const u8`. When null, argv stays `{ "git", "clone", "--", url, dest }`. When set, call `remote.validateBranch` then argv `{ "git", "clone", "--branch", branch, "--", url, dest }`. Update `from.fetchText` to pass `null`.
   - Add `pub fn checkoutBranch(io, allocator, environ, runner, dest, branch, fail)`. Behaviour: refuse detached HEAD and a dirty tree with the same wording `fetchUpdate` already uses (extract a private `refuseDetachedOrDirty` used by both, or duplicate the two git calls — prefer extract if it stays in this file). Then `git fetch`. Then `git checkout --track -B <branch> origin/<branch>` (argv array, branch already validated). Non-zero exit is a Failure that includes git stderr. This is what `add --branch` uses when dest already exists and what `update --branch` / `install` of a `branch:` row use.
   - `fetchUpdate` stays the no-flag update path (ff-only `@{upstream}`).

   Callers of `clone` in this step: `from.zig` (`null`), tests in `git.test.zig`. `shared.ensureCloned` is updated in step 6.

   Compile and `zig build test` before marking complete.

5. **Absolute local paths.** In `src/lib/files.zig`, add `pub fn absolutePath(allocator, cwd: []const u8, path: []const u8)`. If `std.fs.path.isAbsolute(path)`, return a dupe of `path`. Otherwise `joinPath` of `cwd` and `path`. Do not `chdir`. Empty `path` is not this function’s job (callers error first).

   Compile and `zig build test` before marking complete.

6. **Linker retargets a namespace symlink.** In `src/lib/link.zig` `placeSymlink`: when `link_path` already exists as a symlink whose target is **not** `dest`, delete that symlink (`removeSymlink`) and create the new one. Keep refusing a real file/directory at `link_path`. Same-target remains a no-op. This is what lets `update --local` / `update --branch` move links between a store dest and a local path without a foreign-link error. `unlinkPackage` is unchanged and still only removes links that point at the dest it is given.

   Compile and `zig build test` before marking complete.

7. **Shared helpers for source dir and clone-or-checkout.** In `src/cmd/shared.zig` (and new `src/cmd/shared.test.zig`, wired with `test { _ = @import("shared.test.zig"); }` at the bottom of `shared.zig`):
   - `pub fn contentDir(ctx, pkg: config.Package) failure.Error![]const u8` — if `pkg.local` is set, `files.absolutePath(ctx.cwd, pkg.local)` (already absolute after write, but still resolve). Else `resolveStore(ctx, pkg.repo).dest`.
   - `pub fn resolveLocal(ctx, path: []const u8) failure.Error![]const u8` — reject empty; `absolutePath`; require `dirExists`; require that path looks like a git work tree (`.git` exists as a file or directory, following a symlink for gitfiles); then `package.scan` so an invalid package fails here. Return the absolute path.
   - Change `ensureCloned` to `pub fn ensureCloned(ctx, spec, branch: ?[]const u8, spinner)`. If dest missing: `git.clone` with that `branch`. If dest exists and `branch` is null: reuse (today’s behaviour). If dest exists and `branch` is set: `git.checkoutBranch`. Progress only for an actual clone.
   - Change `installOne` to: if `pkg.local` is set, `resolveLocal` that path, scan (already done), `linkPackage` with that path; else `ensureCloned(pkg.repo, pkg.branch, …)` then `linkPackage` with the store dest. Print the repo as today.
   - Add `pub fn replacePackage(allocator, file, index, pkg) config.File` that copies the slice and replaces `packages[index]` (used by `update` YAML rewrites). Or keep that private to `update.zig` if it is only used there — then test it through `update.run`.

   Every new `pub` function is tested in `shared.test.zig` via `shared.contentDir` / `shared.resolveLocal` / `shared.ensureCloned` on a `harness.Scenario` (absolute paths from `TemporaryDir`, private `Environ.Map`, no `chdir`). `ensureCloned` tests assert clone argv with and without `--branch`, and that an existing dest plus `branch` records a `checkout` argv.

   Update `src/lib/test/harness.zig` `FakeGit.runGit`: handle `argv[1] == "checkout"` by returning success (and, if dest exists, leave the already-materialized layout). `cloneReply` already uses `argv[argv.len - 1]` as dest, so `--branch` clone still works. `revParseReply` for `--abbrev-ref HEAD` should return the last checked-out branch when tests set `FakeGit.branch: []const u8 = "main"` (default `"main"`); `checkout` updates that field from argv so detached/dirty tests stay valid.

   Compile and `zig build test` before marking complete.

8. **`skl add --branch` and `--local`.** In `src/cmd/add.zig`:
   - `Args`: `branch: ?[]const u8 = null`, `local: ?[]const u8 = null`.
   - `buildCommand`: `.option("--branch <name>", "Clone this branch instead of the default.", null)` and `.option("--local <path>", "Link a local working tree instead of cloning.", null)`.
   - `action`: unpack `invocation.option("branch")` and `option("local")`.
   - `run`: `--from` with `--branch` or `--local` errors (`--branch is not used with --from`, same pattern as `--ns`). `--branch` and `--local` together error. `--local` still requires `<repo>` (and `--ns` as today).
   - Repo path (not `--from`): after namespace checks, if `args.local` is set: `shared.resolveLocal`, do **not** call `ensureCloned`, `appendPackage` with `local` set to the absolute path and `branch` null, `writeFile`, `linkPackage` with the local path.
   - If `args.branch` is set: `remote.validateBranch` (also done inside clone), `ensureCloned(spec, branch)`, scan, `appendPackage` with `branch` set and `local` null, link the store dest.
   - If neither: today’s `ensureCloned(spec, null)` and `{ .repo, .namespace }` only.
   - Update `appendPackage` to take the full `config.Package` (or extra optional fields) so it can write `branch`/`local`.

   Compile and `zig build test` before marking complete.

9. **`skl update --branch` and `--local`.** In `src/cmd/update.zig`:
   - `Args`: `branch: ?[]const u8 = null`, `local: ?[]const u8 = null`.
   - `buildCommand`: same two options as `add`.
   - `run`: `--branch` and `--local` together error. Either flag without `args.query` errors (`update --branch requires a package`).
   - No-flag path: for each selected package, if `pkg.local` is set, `resolveLocal`, `linkPackage` at that path, print `{repo}  local {path}` (or `unchanged` if you prefer not to invent a SHA); do **not** call `fetchUpdate`. Else today’s `fetchUpdate` + SHA line + `linkPackage` at the store dest.
   - `--local` path: `requireOneMatch`, `resolveLocal`, rewrite that YAML row (`local` = absolute, `branch` = null), `writeFile`, `linkPackage` at the local path (retarget from step 6). Print `{repo}  local {abs}`.
   - `--branch` path: `requireOneMatch`, `ensureCloned(pkg.repo, branch)`, rewrite YAML (`branch` = name, `local` = null), `writeFile`, `linkPackage` at the store dest. Print the SHA line like today’s update (old SHA from before checkout if dest existed; if dest was missing, printing the new SHA without an old one is fine — e.g. `{repo}  {newsha}` or `unchanged` when they match).
   - Dirty store tree still errors on `--branch` via `checkoutBranch`. `--local` does not inspect the store tree.

   Compile and `zig build test` before marking complete.

10. **`list`, `docs`, and `remove` use `contentDir`.** In `src/cmd/list.zig` `printPackage`: scan/readme from `shared.contentDir`, not always the store. If that dir is missing, keep the `not installed` note. On the package title line, when `pkg.branch` is set append it (e.g. the repo string plus the branch name); when `pkg.local` is set, print the local path so a local source is visible. In `src/cmd/docs.zig` `printDetails`: same content dir for readme/scan; print `branch: …` or `local: …` when set. In `src/cmd/remove.zig`: `unlinkPackage` using `contentDir` (so a `--local` namespace is actually unlinked). Store clone is still left on disk.

    Compile and `zig build test` before marking complete.

11. **Example GitHub branch.** Skipped. Do not add a `dev` (or any extra) branch on `ashleydavis/skl-example-skills`. README `--branch` examples are generic. Smoke tests in step 12 create a throwaway `dev` branch on the fixture remote.

12. **Smoke tests.** In `scripts/smoke-tests.sh`, add a dedicated throwaway cwd (e.g. `CWD_SOURCE`) so these cases do not depend on `cwd-add` after `remove`. Fixture git (`init` / `add` / `commit` / `config` / `checkout` / `branch`) stays inside `mktemp` dirs via `fixture_git` (extend `fixture_git` to wrap any git argv; keep the `rev-parse --show-toplevel` abort). Never those commands against this checkout. `skl` still runs with `GIT_DIR` and `GIT_WORK_TREE` unset.

    On the existing `REMOTE_SKILLS` fixture, after the initial commit on `main`, create a `dev` branch with a distinct README first paragraph or skill description, then check `main` back out so default-branch tests stay valid. Number new scenarios after the current last one (47):

    - `add acme/skills --ns demo --branch dev` clones, YAML contains `branch: dev` and not `local:`, store HEAD is `dev`, Cursor/Claude links point at the store dest, `list` shows the `dev` content.
    - Second `install` in that cwd is idempotent and stays on `dev`.
    - `update demo --branch main` YAML has `branch: main` and no `local`, store is on `main`, links still at the store, output mentions SHAs or the branch switch.
    - `update demo --local <throwaway work tree>`: create a separate throwaway git work tree (via `fixture_git`) with a valid `skills/` layout and a distinct description; YAML has `local:` with an **absolute** path and no `branch:`; namespace symlink target contains that path, not `github.com/acme/skills`; `list` shows the local description.
    - `update demo --branch main` after local: YAML has `branch: main` and no `local`, links point at the store again.
    - `add acme/skills --ns other --local <path>` (fresh namespace): no new clone required if the store already has `acme/skills`; YAML `local:` absolute; links at the local path.
    - `add --branch` and `--local` together exits non-zero.
    - `update --branch` with no package query exits non-zero.
    - `add --from` with `--branch` exits non-zero.
    - `add --branch nosuchbranch` exits non-zero; YAML unchanged.
    - `update --local` of a missing path exits non-zero; YAML unchanged.
    - Existing scenario 43 (`add /tmp/some-path` as the **repo** positional) still fails: local installs are `--local`, not a filesystem repo spec.

    `./scripts/smoke-tests.sh` (in-tree binary) must pass. Do not put snapshot counts in docs.

13. **Update documentation to match the final code.** Re-read `docs/COMMANDS.md`, `docs/HOW_IT_WORKS.md`, `README.md`, and `HELP_EXAMPLES`. Fix anything that drifted during implementation (flag wording, YAML field names, `list` line format, error phrases smoke tests match). Help text on `add` / `update` must match the options actually registered. Do not document things the code does not do.

    `zig build`, `zig build test`, and `./scripts/smoke-tests.sh --binary` (after `zig build` / `zig build release` as required by the existing scripts) must pass.

## Unit Tests

Every new or changed function is tested through its module (`config.parse`, `git.clone`, not a bare `parse`). Tests own their `TestIo`, `TemporaryDir`, and `Environ.Map`. No `chdir`, no process env mutation, no checkout paths.

- `src/lib/config.test.zig`
  - Parse a row with `branch:` (local null) and a row with `local:` (branch null).
  - Stringify omits unset optional fields (existing `sample_yaml` round-trip bytes unchanged).
  - Stringify then parse round-trips `branch` and `local`.
  - Parse refuses both `branch` and `local` on one row.
  - Parse refuses empty `branch:` / `local:`.
- `src/lib/remote.test.zig`
  - `validateBranch` accepts `main` and `feature/foo`.
  - Rejects empty, `HEAD`, `-n`, `..`, `a//b`, `:`.
- `src/lib/git.test.zig`
  - `clone` without branch: argv still `git clone -- url dest`.
  - `clone` with branch: argv `git clone --branch feature -- url dest`.
  - `checkoutBranch` argv order: `rev-parse --abbrev-ref HEAD`, `status --porcelain`, `fetch`, `checkout --track -B <branch> origin/<branch>`, cwd is dest.
  - `checkoutBranch` refuses detached and dirty with the same phrases as `fetchUpdate`.
- `src/lib/files.test.zig`
  - `absolutePath` returns an already-absolute path unchanged (dupe).
  - Relative path is joined onto `cwd` with `joinPath`.
- `src/lib/link.test.zig`
  - `linkPackage` on a namespace that already points at dest A, then again with dest B, leaves a symlink to dest B (retarget). A real file at the link path still errors.
- `src/cmd/shared.test.zig` (new)
  - `contentDir` with `local` returns that path; without `local` returns the store dest.
  - `resolveLocal` errors on a missing path, a non-directory, a directory without `.git`, and a git dir that fails `package.scan`.
  - `ensureCloned` missing dest without branch: clone argv has no `--branch`.
  - `ensureCloned` missing dest with branch: clone argv includes `--branch`.
  - `ensureCloned` existing dest with branch: no second clone; checkout argv is recorded.
- `src/cmd/add.test.zig`
  - `add` with `--branch` writes `branch:` in YAML, not `local:`; clone argv includes `--branch`.
  - `add` with `--local` writes absolute `local:`, does not clone, links at the local path (symlink target contains that path).
  - `--branch` and `--local` together errors; YAML unchanged.
  - `--from` with `--branch` errors; no clone of skill packages.
  - `--local` without `--ns` when non-interactive still errors `--ns`.
  - Failed `resolveLocal` / scan leaves YAML unchanged.
- `src/cmd/update.test.zig`
  - `--branch` without query errors.
  - `--local` without query errors.
  - `--branch` and `--local` together errors.
  - `--branch main` after an add clears nothing extra on a default row and checks out; YAML `branch: main`.
  - `--local` after add writes `local:`, clears `branch`, links retarget.
  - `--branch` after `--local` clears `local`, sets `branch`, links back to store.
  - No-flag update of a `local:` row does not call fetch (no `git fetch` in `FakeGit.calls`) and still succeeds.
  - No-flag update of a remote row still prints unchanged vs SHA move (existing tests).
- `src/cmd/install.test.zig`
  - YAML with `branch:` clones with `--branch` (or checkouts when dest exists).
  - YAML with `local:` links that path and does not clone.
  - Missing `local` path: error, earlier packages in the file stay linked (partial failure, same as today).
- `src/cmd/list.test.zig`
  - A `local:` row lists items from the local tree, not `not installed`, and the output mentions the local path or makes the source visible.
  - A `branch:` row still lists items from the store.
- `src/cmd/remove.test.zig`
  - Remove of a `--local` package unlinks the namespace (link path gone) and drops YAML; store dest may still exist.
- `src/cmd/docs.test.zig`
  - Details for a `local:` / `branch:` row print that field; items come from `contentDir`.
- `src/main.test.zig`
  - Program help / `add --help` / `update --help` mention `--branch` and `--local`.

## Smoke Tests

Automated in `scripts/smoke-tests.sh` (step 12). Behaviours:

- Install from a named branch (`add --branch`); YAML, store branch, and agent links.
- Idempotent `install` stays on that branch.
- `update --branch` switches the listed package (including back to `main`).
- `update --local` retargets links at a throwaway work tree; YAML stores an absolute `local:` and drops `branch`.
- `update --branch` after `--local` relinks to the store and clears `local`.
- `add --local` for a new namespace.
- Flag errors: both flags, `update --branch` with no query, `add --from --branch`, missing branch name on the remote, missing `--local` path.
- Positional filesystem repo spec still rejected (scenario 43).

React/UI does not apply. No interactive `--ns` prompt in smoke.

## Verify

The executing agent can observe all of the following:

- `zig build` succeeds.
- `zig build test` succeeds (test count moved when `shared.test.zig` was added; do not write that number into docs).
- `./scripts/smoke-tests.sh` passes.
- `./scripts/smoke-tests.sh --binary` passes after `zig build release`.
- `skl add --help` and `skl update --help` list `--branch` and `--local`.
- `docs/COMMANDS.md`, `docs/HOW_IT_WORKS.md`, and `README.md` match the implemented flags and YAML fields.
- `ashleydavis/skl-example-skills` is not given a `dev` branch; README `--branch` examples stay generic.

## Notes

- Installing one package is `skl add`, not `skl install`. `install` has no package argument; putting `--branch` / `--local` there would apply to every row. The flags belong on `add` (first install) and `update` (switch). `install` reads YAML.
- v1 explicitly dropped “local path packages”; this plan reintroduces them as an **opt-in YAML field plus CLI flags**, not as a filesystem string in `repo:`. `remote.parse` still refuses filesystem paths as the repo spec (smoke 43).
- `--local` links at the working tree so skill edits are live. The store clone is not deleted, so `update --branch` can relink without recloning when dest already exists.
- `local` is stored absolute so a later `skl -g install` from another cwd still finds it. Relative `--local` is resolved against `ctx.cwd` at write time.
- `branch` and `local` are mutually exclusive in YAML so `install` has one source. Switching writes one and clears the other; returning from local always requires an explicit `--branch <name>` (no remembered branch).
- `placeSymlink` retarget is a behaviour change: a namespace symlink that pointed elsewhere is replaced rather than refused. A real file at that path is still refused. Two YAML rows cannot share a namespace, so this does not steal another package’s ns.
- Checkout uses `git checkout --track -B <branch> origin/<branch>` after `fetch` so `fetchUpdate` still has `@{upstream}` once the row is remote again. Confirm this argv against the git on PATH during implementation; if git rejects `-B` combined with `--track`, use `git checkout -B <branch> origin/<branch>` (which sets tracking when `origin/<branch>` is the start point) and keep the unit test matched to the argv actually sent.
- `FakeGit` must not require network. Branch content in unit tests can stay the same fixture layout; smoke tests are what assert distinct `dev` vs `main` content.
- Example repos stay under `ashleydavis` as they already are in README; smoke fixtures stay generic `acme/…`.
- Do not edit `AGENTS.md` / `CLAUDE.md` unless a later step truly needs a new rule. Fixture `checkout` / `branch` go through `fixture_git` so they cannot see this checkout.
- Windows: `files.samePath` already treats `/` and `\` as the same separator; local path asserts in smoke should use `assert_symlink`’s substring match, not byte-equal paths.
