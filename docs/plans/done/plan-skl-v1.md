## Implementation Steps

- [x] 0. README — `plan-skl-v1/0-readme.md`
- [x] 1. Example GitHub repos — `plan-skl-v1/1-example-github-repos.md`
- [x] 2. Scaffold the Zig project — `plan-skl-v1/2-scaffold-zig-project.md`
- [x] 3. Vendor Commander and YAML, then extend Commander — `plan-skl-v1/3-vendor-commander-yaml.md`
- [x] 4. Color, icons, TTY, progress — `plan-skl-v1/4-color-icons-tty-progress.md`
- [x] 5. Cross-platform paths — `plan-skl-v1/5-cross-platform-paths.md`
- [x] 6. Git remote parsing (SSH only) and name validation — `plan-skl-v1/6-git-remote-parsing.md`
- [x] 7. Config schema and stow-safe IO — `plan-skl-v1/7-config-schema-stow-io.md`
- [x] 8. Package layout discovery and frontmatter — `plan-skl-v1/8-package-layout-frontmatter.md`
- [x] 9. Git store (clone/fetch via subprocess) — `plan-skl-v1/9-git-store.md`
- [x] 10. Linker — `plan-skl-v1/10-linker.md`
- [x] 11. Wire CLI commands — `plan-skl-v1/11-wire-cli-commands.md`
- [x] 12. `init --from` and `add --from` — `plan-skl-v1/12-init-from.md`
- [x] 13. Scripts and smoke tests — `plan-skl-v1/13-scripts-smoke-tests.md`
- [x] 14. CI and release — `plan-skl-v1/14-ci-and-release.md`
- [x] 15. Update docs — `plan-skl-v1/15-update-docs.md`

# Plan: skl v1 skill package manager

## Overview

Build `skl`, a Zig CLI that installs AI agent skill packages from git. A package is a git repo (name = repo name) containing `skills/` and/or `commands/` trees; those are the same kind of artifact. `skl` clones over SSH into `~/.skilled/store/<host>/<owner>/<repo>/`, then symlinks each tree into Cursor and Claude skill/command directories under a per-package namespace. User intent lives in YAML (`~/.config/skilled/skl.yaml` globally, `./skl.yaml` in a project). There is no package manifest, no bundle type, no registry server, and no company-specific names in this repo. GitHub is the registry.

This checkout already has `CLAUDE.md` and `AGENTS.md` with the full project rules (company-names, comments, test wiring, git-in-scripts, done-means). It does not yet have Zig sources; those are what this plan adds. The old proposal at `ashleydavis/skilled` will be replaced by this implementation. Engineering shape follows the sibling `what-changed` clone: Zig 0.16, `std.process.Init` + threaded `std.Io`, library + thin CLI, Commander.js port, co-located `*.test.zig`, shell smoke tests against the real binary, GitHub Actions release matrix for Linux, macOS, and Windows.

## Issues

- [x] 1. Overview says this repo is empty; `CLAUDE.md` and `AGENTS.md` already exist. Step 1 recreates them with only the company-names rule and would drop the comment, test-wiring, git-in-scripts, and done-means rules already in those files.
- [x] 2. Scaffold and later IO steps never mention Zig 0.16 `std.Io` or `std.process.Init`. what-changed threads `Io` through every filesystem call and `std.process.run`; `git.zig`, `config.writeFile`, `link`, and `main` as described will not compile on 0.16.
- [x] 3. Step 2 forbids an HTTP dependency; step 10 `docs` does HTTP HEAD/GET to GitHub Pages. No HTTP client, no test double. Smoke 36/38 can hit the real network.
- [x] 4. Smoke 35–38 require `SKL_BROWSER`; implementation and README never define that env var (step 10 only names `xdg-open` / `open` / `cmd /c start`).
- [x] 5. `init --from` HTTPS blob URLs include a git `<ref>`, but v1 clones the default branch with no pin/checkout. The file at that ref may be missing or different on default.
- [x] 6. `--from` spec `git@host:owner/repo.git:path/to/file.yaml` already contains colons; the split rule is not stated. Same for `owner/repo:path` vs SSH.
- [x] 7. Step 10 `add` appends YAML then clones; smoke 18 requires a failed add (empty package) not to leave a YAML entry. No rollback or clone-first order is specified.
- [x] 8. `--from` clones the config repo into the store. Config repos typically have no `skills/` or `commands/`; step 7 errors when both are missing. Leftover store clones and whether `scan` runs on that repo are unspecified. Scenario 12 says it does not clone skill packages, but it does clone the config repo.
- [x] 9. Namespace, owner, and repo are not validated (`..`, `/`, `:`, empty, Windows-illegal names). `skills/<ns>` as a symlink can escape agent roots.
- [x] 10. Smoke tests need `git init`, `git commit`, and `git config` `insteadOf` in fixtures. Existing `CLAUDE.md` forbids extra git add/commit that might touch this checkout. The plan does not specify `GIT_DIR` / `GIT_WORK_TREE` / throwaway-`HOME` isolation the way what-changed smoke tests do.
- [x] 11. Smoke scenarios imply shared state (15–21 accumulate packages) but 23 needs a project with `--from` YAML and no links yet. Isolation vs one shared cwd/`HOME` is not specified; 23 fails if it shares the project from 15–22.
- [x] 12. `--open` is listed as a general Command boolean but is docs-only; `--ns` is add-only; `--help` / `--version` already exist on vendored Commander. Flag position (`skl -g add` vs `skl add -g`) is unspecified; smoke uses the prefix form.
- [x] 13. Vendored Commander documents short flags and boolean flags as missing on purpose. `--ns <value>` is a value option (already supported), not a boolean; step 2 and its tests mix the two.
- [x] 14. `update` “relink if HEAD changed” is a no-op if links point at store directories and `linkPackage` is idempotent. Dirty, diverged, or detached store trees and missing `@{upstream}` are unspecified. `fetchUpdate` does not choose among ff-only merge, pull, or reset.
- [x] 15. Package scan: one-level vs recursive `SKILL.md`; empty `skills/` with no `SKILL.md` vs both trees missing; nested command `name` (`plan/create` vs `create`). No frontmatter-extraction step; vendored `yaml.zig` does not parse markdown or multi-line scalars.
- [x] 16. `remove` matching (full repo string vs name vs SSH URL vs `owner/repo`) is unspecified. Same repo under two namespaces is allowed, so remove-by-name can be ambiguous. No match-by-namespace.
- [x] 17. Behavior with no `skl.yaml`, `docs` when the store clone is missing, partial `install` failure (one of N packages), and `init --from` onto a non-empty existing file are unspecified.
- [x] 18. Smoke 3 defers help-with-no-args exit code (“pick one”). Smoke 2 treats `-V` as optional.
- [x] 19. Unit tests omit: HTTP mock, `SKL_BROWSER`, add rollback, missing config, `--from` bad spec / missing file / ignored ref, dirty git, Windows symlink error text, git-not-on-PATH, flag placement, namespace sanitising. Step 10 `src/cmd/*.test.zig` files need the `test { _ = @import(...) }` block; step 1 only wires lib and exe tests.
- [x] 20. Step 14 README omits `SKL_BROWSER`, `XDG_CONFIG_HOME`, Windows Developer Mode, missing-config behavior, and `--from` ref semantics. Verify step 5 (`rg` for real names) would match `ashleydavis` in this plan. Later steps do not keep `AGENTS.md` in sync with `CLAUDE.md`.
- [x] 21. Git/browser must not be spawned via a shell; plan is safe only if argv arrays are used. Constructed Pages/repo URLs from unsanitised `owner`/`repo` are opened in a browser and fetched over HTTP. Stow write-through overwrites whatever the symlink points at. `sshKeyLooksMissing` only checks a few default key filenames, not agent or `IdentityFile`.

## Steps

0. **README.** Create `README.md` from the v1 design before any Zig code: what `skl` is; store / YAML / symlink layers; package layout (`skills/` one-level `SKILL.md`, `commands/` recursive `.md`); YAML example with generic `acme` names; command table (`init`, `install`/`i`, `add`, `remove`, `update`, `list`, `docs`); `--from` including colon-split rules and that a blob `<ref>` is read via `git show`; `-g`; `--ns`; `--non-interactive`; `--no-color` / `NO_COLOR`; `SKL_BROWSER`; `XDG_CONFIG_HOME`; store is `~/.skilled/store` (not `XDG_DATA_HOME`); SSH requirement; namespace uniqueness per config file; missing-config → run `skl init`; stow-safe config writes (without mentioning any personal tools repo); Windows Developer Mode for symlinks; planned build/test commands. Placeholder for install-from-Pages until the user supplies the `gh` one-liner. Do not put GitHub usernames in the README. If this step edits `CLAUDE.md`, edit `AGENTS.md` to match. Do not require `zig build`.

1. **Example GitHub repos.** Create public `ashleydavis/skl-example-skills` (valid package: `README.md` plus `skills/hello/SKILL.md` with a single-line frontmatter `description`) and `ashleydavis/skl-example-config` (`my-team/skl.yaml` listing `ashleydavis/skl-example-skills` under namespace `demo`). Separate repos, not trees inside this checkout. README Getting Started uses `skl add ashleydavis/skl-example-skills --ns demo`, `skl init --from` the config blob URL, and `skl add --from` the same URL after a bare `skl init`. Smoke-test fixtures in step 13 stay generic `acme/…`. No `zig build` required.

2. **Scaffold the Zig project (what-changed layout).** Create `mise.toml` pinning `zig = "0.16.0"`, `build.zig`, `build.zig.zon` (package name `.skilled`, minimum Zig 0.16.0), `.gitignore` (include `zig-out/`, `.zig-cache/`, `bin/`). In `build.zig`, add a library module rooted at `src/lib/lib.zig`, an executable module rooted at `src/main.zig` named `skl` that imports the library, `zig build test` running both lib and exe tests, `zig build run`, and a `release` step that copies the optimised binary to `bin/<arch>/<os>/skl` (`.exe` on Windows) the same way what-changed does.

    Copy `src/lib/files.zig` + `files.test.zig` from the sibling `what-changed` clone (slim if needed, but keep `readFile`, `fileExists`, `describeError`, `MAX_FILE_BYTES`, and `TestIo`). Zig 0.16 requires an `std.Io` on every filesystem call and on `std.process.run`. The CLI creates exactly one Io from `std.process.Init` in `main` and passes it; tests use `TestIo`. Do not call the old 0.14-style `std.fs` APIs that no longer compile.

    Add `src/lib/lib.zig` (re-exports), `src/lib/version.zig` with `pub const version = "0.0.1";`, `src/main.zig` with `pub fn main(init: std.process.Init) u8` that prints version and exits 0 (arena from `init.arena`, writers from `init.io`), plus `src/main.test.zig` and `src/lib/version.test.zig`. Each `.zig` file that has a sibling `*.test.zig` ends with `test { _ = @import("….test.zig"); }`. `lib.zig` also `refAllDecls` so lib tests run.

    **Do not recreate `CLAUDE.md` or `AGENTS.md`.** They already contain the company-names rule plus comments, test-wiring, git-in-scripts, and done-means. Keep both files in lockstep: any later step that edits one edits the other in the same change. The only git-in-scripts tweak this plan needs (same edit in both files): fixture git in `scripts/smoke-tests.sh` may `init` / `add` / `commit` / `config` **only** inside `mktemp` dirs with `GIT_DIR` and `GIT_WORK_TREE` set to those dirs; abort if `git rev-parse --show-toplevel` is not that throwaway path. Never run those commands against this checkout. `skl` itself is invoked with `GIT_DIR` and `GIT_WORK_TREE` unset.

    Run `zig build` and `zig build test`.

3. **Vendor Commander and YAML from what-changed, then extend Commander.** Copy from the sibling clone, smallest set that compiles:

    - `commander.zig` + `commander.test.zig`
    - `yaml.zig` + `yaml.test.zig`
    - `value.zig` + `value.test.zig` (YAML depends on it)
    - `failure.zig` + `failure.test.zig` (YAML depends on it)

    Keep the Commander help layout and error types (`Displayed`, `Refused`). Vendored Commander **already has** value options (`--ns <namespace>`), `--help`, and `--version`. Do not reimplement those. It is **missing on purpose** today: boolean flags, short flags, and `.opts()` inheritance.

    Extend `Command` with three things, tested separately:

    1. **Boolean flags.** If the flags string has no `<placeholder>`, the option takes no value. Presence stores `"true"`; absence is `null` (unless a default is set). v1 booleans: `--global` / `-g`, `--no-color`, `--non-interactive` / `-n`, `--open`. `--no-color` is its own flag, not a negatable `--color`.
    2. **Short flags.** Parse `-g`, `-n`, `-h`, `-V` from a flags string like `"-g, --global"`. Clustering (`-gn`) is out of scope.
    3. **Root-option merge.** Today, options collected before a subcommand name are discarded when descending. Change that: merge the parent's collected values into the child (the omitted `.opts()` inheritance). Unknown options on a subcommand also look up the parent chain. Declare `--global/-g`, `--no-color`, `--non-interactive/-n` once on the root. Both `skl -g add` and `skl add -g` then work.

    Command-specific value/boolean options stay on that command only: `--ns <namespace>` on `add`, `--from <spec>` on `init` and `add`, `--open` on `docs`. `--help` / `--version` stay the existing Commander builtins; version flags are `-V, --version`.

    Unit tests: boolean presence/absence; `-g` combined with `--ns <value>` on `add`; prefix `skl -g add` and suffix `skl add -g` both set global; unknown options still `Refused`; help still `Displayed`; `--ns` still requires a value (it is not a boolean). Do not take a registry or HTTP dependency. Run `zig build` and `zig build test`.

4. **Color, icons, TTY, progress.** Add `src/lib/term.zig` with `pub const Style = struct` holding whether color/icons are enabled. `detectStyle(args, env, stdout_is_tty)` turns color **off** when any of: `--no-color`, env `NO_COLOR` set (any value), env `SKL_NO_COLOR=1`, stdout is not a TTY. Icons (Unicode: check, cross, arrow, package) are off whenever color is off. `pub fn nonInteractive(args, env, stdin_is_tty)` is true when `--non-interactive` / `-n`, env `SKL_NONINTERACTIVE=1`, or stdin is not a TTY. Add `src/lib/progress.zig` with `Progress` that writes a single-line spinner/step text to **stderr** during clone/link (`Cloning owner/repo…`, `Linking ns/name…`) and clears the line on finish. Progress takes `*std.Io.Writer` (stderr), not a hidden handle. Progress is a no-op when non-interactive, stderr is not a TTY, or color/style is disabled. Never write progress to stdout. Unit-test `detectStyle` and `nonInteractive` against fake env/args; unit-test progress no-op vs write using a buffer. Run `zig build` and `zig build test`.

5. **Paths (cross-platform).** Add `src/lib/paths.zig`. Home directory: `HOME`, else `USERPROFILE` (Windows). Config file: `$XDG_CONFIG_HOME/skilled/skl.yaml` if `XDG_CONFIG_HOME` is set, else `<home>/.config/skilled/skl.yaml` on **all** platforms (Windows included) so a stow-managed `~/.config` tree works. Store root: `<home>/.skilled/store` on purpose — v1 does **not** honour `XDG_DATA_HOME`. Project config: `<cwd>/skl.yaml`. Global agent roots: `<home>/.cursor/skills`, `<home>/.cursor/commands`, `<home>/.claude/skills`, `<home>/.claude/commands`. Project agent roots: `<cwd>/.cursor/skills`, `<cwd>/.cursor/commands`, `<cwd>/.claude/skills`, `<cwd>/.claude/commands`. **Never** write under `<home>/.cursor/skills-cursor/` (Cursor-managed). Store clone path: `<store>/<host>/<owner>/<repo>/` where `github.com` and `github.example.com` are ordinary directory names (valid on Linux, macOS, Windows). Use `std.fs.path` / `std.Io.Dir.path` separators. Add `scopeFromFlag(global: bool, cwd)` returning a struct of config path + four agent roots. Unit-test path joins with a fake home/cwd, including a dotted host segment. Run `zig build` and `zig build test`.

6. **Git remote parsing (SSH only) and name validation.** Add `src/lib/remote.zig`. Accept:

    - `owner/repo` → clone URL `git@github.com:owner/repo.git`, host `github.com`, owner, repo.
    - `git@host:owner/repo.git` or `git@host:owner/repo` → use as-is; host/owner/repo parsed from it.

    Reject HTTPS, `github:owner/repo`, and local filesystem paths with a clear error. Repo name (package name) is the git repo name without `.git`.

    **Validate** `host` labels, `owner`, `repo`, and (in later steps) `namespace` with the same rule: non-empty, not `.` or `..`, no `/`, `\`, or `:`, no Windows-illegal characters `<>"|?*`, and each segment matches `[A-Za-z0-9._-]+`. Host may contain dots (`github.example.com`) but each label is validated; `..` in a host is rejected.     Invalid names error before any clone, symlink, or URL is built. This is what stops `skills/<ns>` from escaping agent roots.

    Never inspect `~/.ssh` or private key files. Git performs SSH authentication. Unit-test parse success/fail cases, rejected `..` / `/` / `:`, and store path mapping `git@github.example.com:acme/skills.git` → `.../store/github.example.com/acme/skills`. Run `zig build` and `zig build test`.

7. **Config schema and stow-safe IO.** Add `src/lib/config.zig`. YAML shape (list of objects, not a map):

    ```yaml
    packages:
      - repo: owner/repo
        namespace: demo
      - repo: git@github.example.com:acme/skills.git
        namespace: pla
    ```

    Types: `pub const Package = struct { repo: []u8, namespace: []u8 }; pub const File = struct { packages: []Package };`. `parse(allocator, text)` and `stringify(allocator, file)` using the vendored YAML parser. **Namespace uniqueness** is per config file: two entries with the same `namespace` is an error. `readFile(io, path)` follows symlinks (`open` the path) and is bounded by `files.MAX_FILE_BYTES`. `writeFile(io, path, file)` is **stow-safe**: resolve `path`; write through only when the resolved target is a **regular file** (or `path` does not exist yet). If `path` is a symlink to a regular file, open that path, truncate, write bytes, close — **do not** write a tempfile and `rename` over `path` (that would replace a stow symlink with a regular file). If `path` does not exist, `makePath` the parent directory then create the file. If `path` is a symlink to a directory, a dangling symlink, a device, or anything other than a regular file, **error** rather than overwrite. Never delete and recreate `skl.yaml`. Unit-test parse/stringify round-trip, duplicate namespace error, write-through (symlink still a symlink, target updated), and refuse write-through to a symlink-to-directory. Run `zig build` and `zig build test`.

8. **Package layout discovery and frontmatter.** Add `src/lib/frontmatter.zig` and `src/lib/package.zig`. Vendored `yaml.zig` does not parse markdown or multi-line scalars, so frontmatter is a separate step: if a file starts with `---\n`, take bytes until the next `\n---\n` (or `\n---\r\n`); parse that inner mapping with `yaml.zig`; read `description` only when it is a plain or quoted **single-line** scalar. If the fence is missing, the YAML fails, or `description` is absent, fall back to the first paragraph of the body (text up to the first blank line). Multi-line YAML scalars in frontmatter are unsupported in v1 and fall back to the body.

    After a clone, a valid package has a top-level `skills/` directory and/or a top-level `commands/` directory. **Error only when both are missing as directories.** An empty `skills/` (no `SKILL.md`) is still a skills tree: link it, `scan` may return no skill items. Same for an empty `commands/`.

    Treat the two trees as the same kind of artifact, with different fan-out:

    - **Skills (one level):** each **immediate** subdirectory of `skills/` that contains `SKILL.md` is a skill. Nested `skills/a/b/SKILL.md` is ignored.
    - **Commands (recursive):** each `*.md` file under `commands/` is a command. `name` is the path relative to `commands/` with `.md` stripped, using `/` (`commands/plan/create.md` → `plan/create`, not `create`).

    Package description: first sentence/paragraph of repo `README.md` / `readme.md` (fallback: none; GitHub is not queried). Skill/command description: frontmatter `description` else first paragraph of the body.

    `pub const Item = struct { kind: enum { skill, command }, rel_path: []u8, name: []u8, description: []u8 };` and `scan(io, allocator, pkg_root) []Item`. Unit-test with temp fixtures: skills-only, commands-only, both, both-trees-missing (error), empty `skills/` present (valid, zero skill items), nested `commands/plan/create.md` named `plan/create`, ignored nested `SKILL.md`, missing README, single-line frontmatter description, missing frontmatter falls back to body. Run `zig build` and `zig build test`.

9. **Git store (clone/fetch via subprocess).** Add `src/lib/git.zig` wrapping `git` on `PATH`. Every spawn is `std.process.run` with an **argv array** and `environ_map` — never a shell, never interpolated into `sh -c`. Pass `io: std.Io`.

    - `clone(io, environ, url, dest)` runs `git clone -- <url> <dest>` (create parent dirs first).
    - `showFile(io, environ, repo, ref, path)` runs `git show -- <ref>:<path>` and returns stdout (used by `init --from` and `add --from`, not by package install).
    - `fetchUpdate(io, environ, dest)`:
      1. If `git rev-parse --abbrev-ref HEAD` is `HEAD`, error (detached).
      2. If `git status --porcelain` is non-empty, error (dirty); do not merge.
      3. If `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}` fails, error (no upstream).
      4. `git fetch`.
      5. `git merge --ff-only @{upstream}`. Non-fast-forward (diverged) is an error; do not reset, do not pull.
    - `headSha(io, environ, dest)` via `git rev-parse HEAD`.

    Unit-test argument construction and error mapping with a fake runner interface (`GitRunner` with a function pointer or struct of callbacks) so tests do not hit the network. Cases: clone argv uses `--`; dest path is `store/host/owner/repo`; fetchUpdate refuses dirty / detached / missing upstream; ff-only argv; `git` not on PATH maps to a readable error. Run `zig build` and `zig build test`.

10. **Linker.** Add `src/lib/link.zig`. Namespace is already validated in step 6, so `skills/ns` cannot contain `..`. For a package with namespace `ns` and store path `store_dir`:

    - If `store_dir/skills` exists as a directory, ensure agent `skills/` is a **real directory**, then create `skills/ns` → `store_dir/skills` (one symlink per package, not per skill). Same for `commands/ns` → `store_dir/commands`.
    - Do this for both Cursor and Claude roots in the active scope (global or project).
    - Logical id `ns:name` is **not** a filename; on disk the namespace is a directory (`ns/name`). That is the portable colon normalisation (Windows forbids `:` in names).
    - `linkPackage` is idempotent: if the symlink already points at the correct dest, leave it; if it points elsewhere or is a real file, error (do not `--adopt`).
    - `unlinkPackage` removes only `skills/ns` and `commands/ns` if they are symlinks owned by this scheme (symlink to the store). Do not delete store clones on remove (other scopes may still use them). Do not touch `skills-cursor`.
    - Creating parent `.cursor` / `.claude` as real directories (never a single symlink to the store) — same tree-folding hazard GNU stow has.

    Unit-test with temp dirs: create links, idempotent second link, unlink, refuse clobbering a real file, project vs global roots. On Windows, if symlink creation fails, surface an error telling the user to enable Developer Mode; do not silently copy. Unit-test that the Windows error **text** mentions Developer Mode (fake the syscall failure). Run `zig build` and `zig build test`.

11. **Wire CLI commands in `src/main.zig` using Commander.** Context struct holds allocator, `io: std.Io`, `environ`, cwd, home, style, non_interactive, global flag. `main(init: std.process.Init)` builds that from the process. Subcommands (binary name `skl`):

    **Missing `skl.yaml`:** `install`, `add`, `remove`, `update`, `list`, and `docs` error (exit 1) with `no skl.yaml; run skl init`. `init` is what creates it.

    - `skl init` — write `skl.yaml` with `packages: []` if missing. If `--from <spec>`, create the file from that YAML when missing or still `packages: []` (see step 12). If the file already lists packages, `--from` errors; use `skl add --from`. `-g` selects global config path. Plain `init` refuses to wipe a file that already lists packages. Stow-safe write.
    - `skl install` / `skl i` — read active `skl.yaml`, clone/update every package into the store, link each namespace into that scope’s Cursor and Claude dirs. Progress on stderr. Idempotent. On partial failure (package *k* of *N* fails): stop, exit 1, **keep** packages 1..*k-1* already cloned/linked (no rollback), print which package failed. Next `install` continues the rest.
    - `skl add <repo>` — require `--ns <namespace>` (validated as in step 6). If `--ns` omitted: prompt on TTY when interactive; **error** (exit 1, no hang) when non-interactive. Reject if namespace already in this `skl.yaml`. **Clone + `scan` first**, then append YAML (stow-safe) and link. If clone or scan fails, do **not** write a YAML entry. A successful clone of an invalid package (no `skills/` and no `commands/`) may leave a store clone (same as `remove` leaving the store); YAML is unchanged. If the clone fails, there is no store dest.
    - `skl add --from <spec>` — step 12. Mutually exclusive with `<repo>` / `--ns`. Append packages from the fetched YAML; keep existing entries. Do not clone or link; the user runs `skl install`.
    - `skl remove <query>` — match using the rules in the remove paragraph below; unlink namespace; remove that one YAML entry. Leave store clone.
    - `skl update [repo]` — `fetchUpdate` in store for one package or all in the active YAML. Store-dir symlinks already show new files after a fast-forward; still call `linkPackage` (idempotent no-op if links are correct) so a missing link is repaired. Print `name  oldsha → newsha` or unchanged. Dirty / detached / diverged / no-upstream: exit 1 for that package with the `fetchUpdate` error; do not reset.
    - `skl list` — print each package (name, namespace, repo, description) and each skill/command using the logical id `ns:name` (nested command `commands/plan/create.md` under namespace `cmd` is `cmd:plan/create`). Colors/icons when enabled. Missing store clone: still print the YAML row; item list is empty with a note that it is not installed.
    - `skl docs [package]` — **no HTTP.** There is no Pages probe, no HEAD/GET, no HTTP client. If no args and interactive: menu of packages, Enter selects. Always print package details (from YAML + scan if the store clone exists; if the clone is missing, print YAML fields and skip item descriptions — `--open` still works). Print a GitHub Pages **guess** (`https://<owner>.github.io/<repo>/`) as text only, never fetch it. If `--open`: skip prompt and open a browser to the **git repo HTTPS URL** (see URL rules below). Else if interactive: ask whether to open that same repo URL. Non-interactive without a package name: error.
    - Global options on the root command: `--global` / `-g`, `--no-color`, `--non-interactive` / `-n`, `--version` / `-V`. Bare `skl` (no args) prints help and exits **0** (`Displayed`).

    **Browser spawn.** Never a shell. If env `SKL_BROWSER` is set to a non-empty path, spawn argv `{ SKL_BROWSER, url }`. Else: Linux `xdg-open`, macOS `open`, Windows argv `{ "cmd.exe", "/C", "start", "", url }` (empty title argument so `start` does not eat the URL). `std.process.run` with that argv and `io`. Smoke tests set `SKL_BROWSER` to a stub that appends argv to a log file.

    **Repo URL for `--open`.** Built only after owner/repo/host pass step 6 validation. `owner/repo` or `git@github.com:…` → `https://github.com/<owner>/<repo>`. Other SSH hosts → `https://<host>/<owner>/<repo>`. Never interpolate unsanitised strings into a URL.

    **`remove` matching.** Compare the query, in order, against each YAML entry:

    1. Exact `repo` field string.
    2. Canonical SSH URL for that entry.
    3. `owner/repo` shorthand.
    4. Repo name (last path segment, `.git` stripped).
    5. Namespace.

    If exactly one entry matches, remove it. If more than one matches (same repo under two namespaces, or query equals both a name and a different entry's namespace), error listing the matches and tell the user to pass a unique `owner/repo` or the namespace. `skl remove nosuch` exits non-zero. There is no `--ns` flag on remove; namespace match is by the query string.

    Split command implementations into `src/cmd/init.zig`, `install.zig`, `add.zig`, `remove.zig`, `update.zig`, `list.zig`, `docs.zig` with matching `*.test.zig`. **Each `src/cmd/*.zig` ends with `test { _ = @import("….test.zig"); }`.** `src/main.zig` imports every cmd module so the exe test step actually runs those blocks (step 2 only wired lib + exe; without the cmd imports the cmd tests never run). Each command function takes explicit `io`, paths, and runners so tests inject temp dirs and fake git. Run `zig build` and `zig build test`.

12. **`init --from` and `add --from`.** The spec locates a YAML file inside a git repo. Clone that repo into a **temporary directory** (not the package store), read one file, delete the temp clone. Do not `scan` the config repo. Do not require `skills/` or `commands/`. Do not link. Do not clone the skill packages listed in the file; the user runs `skl install`.

    `init --from` creates `skl.yaml` when missing or still `packages: []`. If the file already lists packages, error and tell the user to run `skl add --from`. `add --from` requires an existing `skl.yaml`, appends incoming packages, keeps existing entries, skips the same namespace+package, and errors if a namespace is taken by a different repo (YAML unchanged). `<repo>` and `--from` are mutually exclusive; `--ns` is not used with `--from`.

    **Split rules** (first match wins):

    1. Spec starts with `https://` — GitHub UI URL only; the clone is still SSH. `https://github.com/owner/repo/blob/<ref>/path` → host `github.com`, owner, repo, ref, path. `https://github.com/owner/repo/path` (no `/blob/`) → ref defaults to `HEAD`, path is the rest after `owner/repo/`. Reject non-github.com HTTPS hosts in v1.
    2. Spec starts with `git@` — SSH. The first `:` separates `git@host` from `owner/repo`. A **second** `:` (after optional `.git`) starts the file path. Example: `git@github.com:acme/skl-config.git:teams/platform.yaml` → host `github.com`, repo `acme/skl-config`, path `teams/platform.yaml`. No second colon → error (path required).
    3. Otherwise shorthand: split on the **first** `:`. Left is `owner/repo`, right is path. `owner/repo:path/to/file.yaml`. A spec with no colon, or with `owner/repo` only, is an error.

    After the temp clone (default branch, SSH), read the file with `git show -- <ref>:<path>` (`HEAD` when the spec had no ref). If that ref or path is missing, error; do not silently substitute the default-branch file. The temp clone is then deleted even on error.

    Unit-test spec parsing (shorthand, SSH with two colons, blob URL with ref, HTTPS without blob), `git show --` argv, missing file, bad spec, `init --from` onto a file that already lists packages (error, YAML unchanged), and `add --from` merge (keeps existing, appends new, duplicate ns+different repo errors). Run `zig build` and `zig build test`.

13. **Scripts and smoke tests.** Add `scripts/smoke-tests.sh` (what-changed style: real process, assert exit codes, stdout, **and filesystem effects**) and `scripts/test-everything.sh` that runs `zig build`, `zig build test`, then smoke tests. The harness must run on **Linux, macOS, and Windows** (Git Bash on Windows). Every command is smoke-tested; symlink and file operations are asserted as such (`test -L` / `readlink` for namespace links, not merely path existence; YAML and store files are real files). Step 14’s release pipeline runs `./scripts/smoke-tests.sh --binary` on each of those platforms against the artifact that will ship.

    **Isolation (copy the what-changed pattern, then extra git for fixtures):**

    - Throwaway `HOME` (`mktemp -d`, `pwd -P`) for the whole run. Product paths (`~/.skilled`, `~/.config`, `~/.cursor`, `~/.ssh`) all land there.
    - Throwaway `cwd` dirs as in the matrix below — **not** one cwd for every scenario.
    - Fixture remotes live under `$HOME/remotes`, each a bare repo.
    - Every fixture `git init` / `git add` / `git commit` / `git config` is run with `GIT_DIR` and `GIT_WORK_TREE` set to that fixture path. After each, `git rev-parse --show-toplevel` must equal that path or the script aborts. These are the only state-changing git commands; they cannot see this checkout.
    - When invoking `skl`, unset `GIT_DIR` and `GIT_WORK_TREE`. Set `GIT_CONFIG_GLOBAL` to `$HOME/.gitconfig` so `insteadOf` applies and the real user gitconfig is ignored.
    - Product `skl add` stays SSH-only: the harness writes `$HOME/.gitconfig` `url.file://<bare>/.insteadOf git@github.com:` (and a second `insteadOf` for `git@github.example.com:`) so SSH-shaped remotes clone locally.
    - Put `SKL_BROWSER` to a stub script that appends its argv to a log file.
    - Support `--binary` pointing at `bin/<arch>/<os>/skl`.

    **Cwd / HOME matrix** (one shared `HOME` and fixture remotes; several project cwds):

    | Cwd | Scenarios | Notes |
    |-----|-----------|--------|
    | `cwd-flags` | 1–8 | Empty or `skl init` as needed. |
    | `cwd-init` | 9–14, 47 | 9–10 then 12 writes project YAML via `init --from`; 14 is `add --from` blob (idempotent); 47 is `init --from` refused when packages exist; 11/13 write global YAML in `HOME`. |
    | `cwd-add` | 15–22, then 30–38, then 26–29, then 41–44 | Fresh `skl init` (empty packages), accumulate adds. **Update / list / docs run while those packages still exist.** Remove runs after that. 23 must **not** use this cwd. |
    | `cwd-install` | 23–24 | Fresh dir: `init --from` only, **no** `add`, then `install`. |
    | `cwd-add-from` | 45 | `init` then `add --from`. |
    | `cwd-add-from-keep` | 46 | Existing extra package kept across `add --from`. |
    | `cwd-stow` | 39 | Dedicated; global yaml is a symlink. |
    | `cwd-bad-yaml` | 40 | Dedicated invalid `skl.yaml`. |
    | (none extra) | 25, 28, 32, 34 | Use `HOME` global yaml from 11/13/22. |

    26 removes `acme/skills` by full repo string. 27 then removes remaining `acme/cmds` by **repo name** `cmds` (26 and 27 cannot both target `skills` on the same cwd). 31's extra commit is in the **bare fixture remote** with `GIT_DIR`/`GIT_WORK_TREE` set to that remote, never in this checkout. 42 (`add … --ns demo` with `$HOME/.ssh` renamed away) runs **after** 26 so namespace `demo` is free.

    Every CLI feature in v1 has a smoke below. Implement them as numbered scenarios in `scripts/smoke-tests.sh` (one section per number, fail-fast with a clear label).

    Harness fixtures (created once per run):
    - Bare repo `acme/skills` with `skills/demo/SKILL.md` (single-line frontmatter description) and `README.md`.
    - Bare repo `acme/cmds` with only `commands/plan/create.md` (nested command, single-line frontmatter description).
    - Bare repo `acme/both` with both `skills/` and `commands/`.
    - Bare repo `acme/empty` with neither tree (install must fail).
    - Bare config repo `acme/skl-config` with `teams/platform.yaml` listing `packages:` for `acme/skills` (`ns: demo`) and `acme/cmds` (`ns: cmd`).
    - Invalid `skl.yaml` fixture (broken YAML).

    Scenarios:

    **Root / global flags**
    1. `skl --help` (and `skl -h`) lists `init`, `install`, `add`, `remove`, `update`, `list`, `docs`.
    2. `skl --version` and `skl -V` both print `0.0.1`.
    3. `skl` with no args prints help and exits **0**.
    4. `skl nosuch` exits non-zero; stderr mentions unknown command.
    5. `skl --no-color list` (with a valid empty config) stdout contains no ANSI escapes.
    6. `NO_COLOR=1 skl list` same: no ANSI.
    7. `skl -n add acme/skills` without `--ns` exits non-zero; does not hang; stderr asks for `--ns`.
    8. `SKL_NONINTERACTIVE=1 skl add acme/skills` without `--ns` same as 7.

    **init**
    9. `skl init` in a temp project cwd creates `./skl.yaml` with `packages: []`.
    10. Second `skl init` in that dir exits 0 and does **not** wipe a non-empty `packages:` list.
    11. `skl init -g` creates `$HOME/.config/skilled/skl.yaml` (not the project file).
    12. `skl init --from acme/skl-config:teams/platform.yaml` writes those two packages into `./skl.yaml`. Does **not** clone skill packages, does **not** link, does **not** leave a store clone of the config repo (temp clone is deleted).
    13. `skl init -g --from git@github.com:acme/skl-config.git:teams/platform.yaml` writes global YAML (global file is still `packages: []` from 11).
    14. `skl add --from https://github.com/acme/skl-config/blob/main/teams/platform.yaml` after 12: same two packages (idempotent merge; clone still SSH via `insteadOf`; file read via `git show -- main:teams/platform.yaml`).

    **add / install / alias**
    15. `skl add acme/skills --ns demo` (project) clones to `$HOME/.skilled/store/github.com/acme/skills`, appends YAML, creates `./.cursor/skills/demo` and `./.claude/skills/demo` as symlinks into the store. No `commands/demo` because that fixture has no `commands/`.
    16. `skl add acme/cmds --ns cmd` creates `./.cursor/commands/cmd` and `./.claude/commands/cmd` pointing at the store `commands/` tree (nested `plan/create.md` visible through the link). No skills link.
    17. `skl add acme/both --ns both` creates **both** skills and commands namespace links for Cursor **and** Claude.
    18. `skl add acme/empty --ns empty` exits non-zero (no `skills/` or `commands/`); YAML not left with that entry.
    19. `skl add git@github.example.com:acme/skills.git --ns ent` stores under `$HOME/.skilled/store/github.example.com/acme/skills`.
    20. `skl add acme/skills --ns demo` again (duplicate namespace) exits non-zero; YAML unchanged.
    21. `skl add acme/both --ns demo` fails (namespace `demo` already taken). A different repo with a **new** namespace still succeeds (covered by 16–17). v1 does not need to forbid the same repo under two namespaces; uniqueness is namespace-only.
    22. `skl -g add acme/skills --ns demo` links `$HOME/.cursor/skills/demo` and `$HOME/.claude/skills/demo`, not the project dirs; writes `$HOME/.config/skilled/skl.yaml`.
    23. In **cwd-install** (YAML from `--from`, no links yet): `skl install` clones missing packages and creates all namespace links. Idempotent second `skl install` (exit 0, same links).
    24. `skl i` is the same as `skl install` (exit 0 on already-installed project).
    25. `skl -g install` installs from global YAML into global agent dirs only.

    **remove / update / list**
    26. `skl remove acme/skills` unlinks `./.cursor/skills/demo` and `./.claude/skills/demo`, removes the YAML entry, **leaves** the store clone.
    27. `skl remove cmds` (repo **name** only) matches remaining `acme/cmds` and removes it.
    28. `skl -g remove acme/skills` unlinks global agent dirs only; project links if any stay.
    29. `skl remove nosuch` exits non-zero.
    30. `skl update` with HEAD unchanged prints unchanged and exits 0; links still valid.
    31. `skl update acme/skills` after a new commit on the fixture remote (harness commits in the bare repo with `GIT_DIR`/`GIT_WORK_TREE`, then update): store HEAD moves; links still resolve; stdout shows old SHA → new SHA.
    32. `skl -g update` updates packages listed in the global YAML.
    33. `skl list` prints package name, namespace, repo, README description, and each skill/command as `ns:name` + description. Project scope by default. Nested command printed as `cmd:plan/create`.
    34. `skl -g list` lists global packages, not the project file.

    **docs**
    35. `skl docs acme/skills -n` prints package details; does **not** invoke `SKL_BROWSER`.
    36. `skl docs acme/skills --open` invokes the stub browser; argv contains `https://github.com/acme/skills` (repo URL, not a Pages fetch).
    37. `skl docs -n` with no package name exits non-zero (no menu in non-interactive).
    38. `skl docs acme/skills --open` does **not** open a Pages URL: browser argv is the git repo page only. Printed stdout may mention the Pages guess. No network.

    **Safety / IO**
    39. Stow: `~/.config/skilled/skl.yaml` is a symlink to a file in a temp “dotfiles” dir; `skl -g add acme/cmds --ns cmd` leaves it a symlink; target file has the new package.
    40. Invalid project `skl.yaml` → `skl list` exits non-zero with a readable parse error.
    41. `skl add` never creates `$HOME/.cursor/skills-cursor` (assert path does not exist or is untouched).
    42. `$HOME/.ssh` renamed away; `skl add acme/skills --ns demo` still clones via `insteadOf` and exits 0. `skl` does not look at key files.
    43. `skl add /tmp/some-path --ns x` (filesystem path) exits non-zero.
    44. `skl add https://github.com/acme/skills --ns x` exits non-zero.
    45. In **cwd-add-from**: `skl init` then `skl add --from acme/skl-config:teams/platform.yaml` writes those two packages; does **not** clone skill packages or the config repo.
    46. In **cwd-add-from-keep** (yaml already lists `acme/both` under namespace `keep`): `skl add --from acme/skl-config:teams/platform.yaml` keeps `keep` and appends `demo` and `cmd`.
    47. In **cwd-init** after 12: `skl init --from acme/skl-config:teams/platform.yaml` exits non-zero; YAML still has the two packages from 12.

    Interactive-only behaviour (TTY menu, `--ns` prompt, docs “open?” prompt, spinner) is **not** asserted in smoke; unit-test the prompt/skip branches with fake TTY flags instead.

    Run `zig build` and `./scripts/smoke-tests.sh`.

14. **CI and release.** Add `.github/workflows/ci.yml`: on push/PR, **Linux, macOS, and Windows** each run `zig build` and `zig build test` (every public function has unit tests; none are platform-skipped). Add `.github/workflows/release.yml` copied in spirit from what-changed: matrix linux/mac/win, stamp `src/lib/version.zig` from the tag, `zig build release`, upload artifacts; then a **`smoke-tests` job** on a native runner per binary that runs `./scripts/smoke-tests.sh --binary` (Windows: `shell: bash`). Publish the GitHub Release only after that job passes. Enable directory-symlink creation on the Windows runner. Do not skip Windows smoke. Add a GitHub Pages workflow that publishes a **minimal download page** for those binaries (generic; no company names). **Do not** invent a `gh` install one-liner; the README was created in step 0 and product docs are reconciled in step 15 — **ask the user** for the one-liner they want.

15. **Update docs.** Reconcile **all product docs** (`README.md`, `docs/HOW_IT_WORKS.md`, `docs/COMMANDS.md`, and any other files under `docs/` except `docs/plans/`) with the CLI that shipped: `--help` command table, flags and env vars (`SKL_BROWSER`, `SKL_NONINTERACTIVE`, `XDG_CONFIG_HOME`, `--from` / `git show`), store path, SSH, namespaces, missing-config, stow-safe writes, Windows Developer Mode, working build/test commands. README stays slim; architecture lives in `HOW_IT_WORKS.md`; CLI reference lives in `COMMANDS.md`. Insert the user’s `gh` one-liner if they have given it; otherwise keep the placeholder and ask. Do not put GitHub usernames in product docs except the published example repos. If this step edits `CLAUDE.md`, edit `AGENTS.md` to match. Run `zig build`, `zig build test`, and `./scripts/smoke-tests.sh --binary`.

## Unit Tests

Every public function is unit-tested (`zig build test` on Linux, macOS, and Windows). None of these are skipped by OS.

- `version.test.zig`: `version` string is non-empty / equals `0.0.1`.
- `commander.test.zig`: existing what-changed cases plus boolean flags, short flags, `-g` prefix and suffix, `--ns` value (not a boolean), `--from` on `init` and `add`, `--open` on docs only, `--non-interactive`, help `Displayed`, unknown option `Refused`.
- `term.detectStyle`: default TTY on; `--no-color`; `NO_COLOR`; `SKL_NO_COLOR`; non-TTY.
- `term.nonInteractive`: flag, env, non-TTY stdin.
- `progress`: no-op when disabled; writes to buffer when enabled.
- `paths`: home/config/store/agent roots; `XDG_CONFIG_HOME`; Windows `USERPROFILE` fake; host `github.example.com` in store path; store ignores `XDG_DATA_HOME`.
- `remote.parse`: `owner/repo`, SSH URL, reject https, reject filesystem path; package name strips `.git`; reject `..`, `/`, `:`, empty, Windows-illegal names.
- `config.parse` / `stringify`: list of `{repo, namespace}`; duplicate namespace error.
- `config.writeFile`: symlink still a symlink after write; target updated; refuse symlink-to-directory.
- `frontmatter`: single-line YAML description; missing fence falls back to first paragraph; multi-line scalar falls back.
- `package.scan`: skills (one-level), commands (recursive name `plan/create`), both, both-missing error, empty `skills/` valid, nested `SKILL.md` ignored, README description, SKILL.md frontmatter description.
- `git.clone` / `fetchUpdate` / `headSha` / `showFile`: fake runner argv assertions; dirty / detached / no-upstream errors; git-not-on-PATH.
- `link.linkPackage` / `unlinkPackage`: idempotent link, refuse clobber, both agents, skills+commands, project roots; Windows Developer Mode error text.
- `cmd/init`: creates YAML; `--from` spec parse (shorthand, SSH two-colon, blob ref); missing file; bad spec; `init --from` errors when packages are already listed; fills `packages: []`.
- `cmd/add`: requires ns when non-interactive; duplicate ns error; clone-then-YAML (failed scan leaves YAML unchanged); invalid namespace rejected; `--from` after init appends; keeps existing extra package; namespace taken by a different repo errors; `--from` with `<repo>` or `--ns` errors.
- `cmd/install`: links all packages in fixture YAML; missing config errors; partial failure keeps earlier packages.
- `cmd/remove`: unlinks and drops YAML entry; match by repo string, name, SSH, namespace; ambiguous match errors.
- `cmd/update`: unchanged SHA vs changed SHA; dirty tree errors.
- `cmd/list`: formats package + items as `ns:name` (nested command `cmd:plan/create`); missing config; missing store clone still prints YAML row.
- `cmd/docs`: `--open` calls opener with **repo** URL; `SKL_BROWSER` argv; menu skipped when non-interactive without name; missing clone still allows `--open`; no HTTP client in the module.

## Smoke Tests

`scripts/smoke-tests.sh` implements **every v1 CLI command** as numbered scenarios 1–47 in step 13. The release pipeline runs that suite with `--binary` on Linux, macOS, and Windows. Symlinks and file operations are part of those scenarios, not Unix-only extras.

| Area | Scenarios |
|------|-----------|
| Help, version (`--version` and `-V`), unknown command, bare `skl` exits 0 | 1–4 |
| `--no-color`, `NO_COLOR`, `-n`, `SKL_NONINTERACTIVE` | 5–8 |
| `init`, `init -g`, `init --from` (path, SSH URL); `add --from` blob URL (idempotent); `init --from` refused when packages exist | 9–14, 47 |
| `add` skills-only, commands-only, both, empty fail (no YAML leftover), enterprise host, duplicate ns | 15–21 |
| `add -g`, `install` in a **separate** cwd, alias `i`, `install -g` | 22–25 |
| `update` unchanged, SHA moved, `-g` (while project packages still exist) | 30–32 |
| `list`, `list -g` | 33–34 |
| `docs` print, `--open` repo URL via `SKL_BROWSER`, `-n` no name, no Pages fetch | 35–38 |
| `remove` (repo string, remaining name `cmds`, `-g`, missing) **after** update/docs | 26–29 |
| Stow write-through, bad YAML, never `skills-cursor`, add without `~/.ssh`, reject path/https | 39–44 |
| `init` then `add --from`; existing extra package kept | 45–46 |

Not in smoke (unit-test with fake TTY flags): interactive `--ns` prompt, docs menu, docs “open?” prompt, spinner. Fixture remotes are SSH-shaped via git `insteadOf` to local bare repos (no network). `SKL_BROWSER` stub records argv; docs never hits the network.

The same numbered suite runs on Linux, macOS, and Windows in the **release pipeline** via `./scripts/smoke-tests.sh --binary` against the artifact that will ship (what-changed `smoke-tests` job). Namespace links must be native directory symlinks (not copies). Stow write-through, store clones, YAML writes, and unlink leaving the store are asserted as file operations on every platform.

## Verify

1. `zig build` succeeds.
2. `zig build test` — all unit tests pass on every platform CI runs. Every public function is unit-tested. Confirm the test count moved when adding each `*.test.zig` (the `test { _ = @import(...) }` block counts as one test of its own).
3. `./scripts/smoke-tests.sh` and `./scripts/smoke-tests.sh --binary` pass locally. In the **release pipeline**, `--binary` runs on Linux, macOS, and Windows against the artifact that will ship (what-changed `smoke-tests` job). No platform skips that job.
4. `./scripts/test-everything.sh` passes.
5. `rg` **product paths** (`src/`, `scripts/`, `README.md`, `CLAUDE.md`, `AGENTS.md`, `.github/`) for real company, department, or team names — no matches (generic `acme` examples only). Exclude `docs/plans/` so this plan's citations of the sibling `what-changed` / `skilled` GitHub repos do not fail the check. `CLAUDE.md` and `AGENTS.md` are identical in substance.

## Notes

- **Old `ashleydavis/skilled` proposal — keep:** three layers (store, config, links); never copy into agent dirs; idempotent install; git is the registry; symlink-only; do not touch Cursor’s built-in skills dir; Zig lib + thin CLI; co-located unit tests; smoke tests against the real binary; release matrix Linux/macOS/Windows; install = resolve → fetch → link; update = fetch (ff-only) and repair links; remove unlinks and does not uninstall the `skl` binary; `commands/` is a first-class tree (not optional in the product sense — packages may omit a tree but the linker always targets Claude/Cursor `commands/` when `commands/` exists in the package); skills and commands are the same kind of thing.
- **Old proposal — drop:** package vs bundle; `skilled.pkg.toml` / `skilled.bundle.toml`; TOML; `~/skills-repo` hierarchy keyed by org/dept/team; lock file; doctor/search/uninstall/bootstrap/discovery; permissions/instructions/settings/rules exports; local path installs; `github:` source scheme as the primary UI; GitHub API discovery; company/org names; restructuring agent-config in this repo; docs generator.
- **Old `notes.md`:** treat as non-binding. Interview overrides it. Do not copy those repo names into this codebase.
- **Stow:** global config must survive `stow` from a personal tools repo. Write through existing inodes/symlinks only when the target is a regular file. Do not mention that tools repo in this project’s docs.
- **Reuse GitHub repo:** implementing here is intended to replace the current proposal-only `ashleydavis/skilled` contents.
- **README install one-liner:** ask the user for the `gh` snippet in step 0 and again in step 15 if it is still a placeholder (they requested that). Step 15 updates all product docs, not only `README.md`.
- **v1 out of scope:** version pins/semver ranges, lock file, doctor, search, GitHub API, HTTP of any kind, docs generation, permissions, local path packages, sharing a namespace across packages, inferring `--ns`, clustering short flags, `XDG_DATA_HOME` for the store, inspecting `~/.ssh` / private keys / `ssh-agent` / `IdentityFile`.
- **Testing:** every public function has unit tests. Every CLI command is smoke-tested against the real binary (`--binary`), including symlink and file operations. The release pipeline runs that suite on Linux, macOS, and Windows (what-changed `smoke-tests` job) before publish.
- **Windows symlinks:** require Developer Mode or equivalent for users; fail clearly rather than copying files. Release-pipeline Windows runners must have that privilege so `--binary` smoke actually creates and asserts directory symlinks — do not skip that job.
- **Zig 0.16:** `main` is `pub fn main(init: std.process.Init) u8`. Thread `init.io` through every filesystem call and `std.process.run`. Tests use `files.TestIo`.
- **Spawn:** git and the browser are always argv arrays. No `sh -c`.
- **AGENTS.md:** keep identical in substance to `CLAUDE.md` whenever either changes.
