# 13. Scripts and smoke tests

## Goal

Add a real-binary smoke harness (what-changed style) and a `test-everything` wrapper. Every v1 CLI command has a numbered scenario. Isolation must not touch this checkout. The same suite must run on **Linux, macOS, and Windows** (Git Bash on Windows). Symlinks and other file operations are asserted as such on every platform — not skipped on Windows.

## Files

- `scripts/smoke-tests.sh`
- `scripts/test-everything.sh` — runs `zig build`, `zig build test`, then smoke tests.

If step 2 already documented the git-in-scripts rule in `CLAUDE.md` / `AGENTS.md`, follow it. If those files still only mention a marked `git init`, update both in lockstep to the isolation rules below.

## Isolation (copy the what-changed pattern, then extra git for fixtures)

- Throwaway `HOME` (`mktemp -d`, `pwd -P`) for the whole run. Product paths (`~/.skilled`, `~/.config`, `~/.cursor`, `~/.ssh`) all land there.
- Throwaway `cwd` dirs as in the matrix below — **not** one cwd for every scenario.
- Fixture remotes live under `$HOME/remotes`, each a bare repo.
- Every fixture `git init` / `git add` / `git commit` / `git config` is run with `GIT_DIR` and `GIT_WORK_TREE` set to that fixture path. After each, `git rev-parse --show-toplevel` must equal that path or the script aborts. These are the only state-changing git commands; they cannot see this checkout. This marked fixture git is the only git that may change state in a way that could touch a real checkout — and the abort check exists so it cannot.
- When invoking `skl`, unset `GIT_DIR` and `GIT_WORK_TREE`. Set `GIT_CONFIG_GLOBAL` to `$HOME/.gitconfig` so `insteadOf` applies and the real user gitconfig is ignored.
- Product `skl add` stays SSH-only: the harness writes `$HOME/.gitconfig` `url.file://<bare>/.insteadOf git@github.com:` (and a second `insteadOf` for `git@github.example.com:`) so SSH-shaped remotes clone locally.
- Put `SKL_BROWSER` to a stub script that appends its argv to a log file.
- Support `--binary` pointing at `bin/<arch>/<os>/skl` (`.exe` on Windows).
- Run under Git Bash on Windows as well as `/bin/sh` on Unix. Do not maintain a separate skipped Windows path.
- Assert filesystem effects, not only exit codes: namespace links are native directory **symlinks** (`test -L` / `readlink`, not a copied tree); YAML and store paths are the expected files; `remove` unlinks and leaves the store; stow write-through leaves a symlink. CI Windows must be able to create directory symlinks.

## Cwd / HOME matrix

One shared `HOME` and fixture remotes; several project cwds:

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

Implement numbered scenarios in `scripts/smoke-tests.sh` (one section per number, fail-fast with a clear label).

## Harness fixtures (created once per run)

- Bare repo `acme/skills` with `skills/demo/SKILL.md` (single-line frontmatter description) and `README.md`.
- Bare repo `acme/cmds` with only `commands/plan/create.md` (nested command, single-line frontmatter description).
- Bare repo `acme/both` with both `skills/` and `commands/`.
- Bare repo `acme/empty` with neither tree (install must fail).
- Bare config repo `acme/skl-config` with `teams/platform.yaml` listing `packages:` for `acme/skills` (`ns: demo`) and `acme/cmds` (`ns: cmd`).
- Invalid `skl.yaml` fixture (broken YAML).

## Scenarios

**Root / global flags**

1. `skl --help`, `skl -h`, and `skl help` list `init`, `install`, `add`, `remove`, `update`, `list`, `docs`, `help`, `version`.
2. `skl --version`, `skl -V`, and `skl version` all print `0.0.1`.
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

**`add --from`**

45. In **cwd-add-from**: `skl init` then `skl add --from acme/skl-config:teams/platform.yaml` writes those two packages; does **not** clone skill packages or the config repo.
46. In **cwd-add-from-keep** (yaml already lists `acme/both` under namespace `keep`): `skl add --from acme/skl-config:teams/platform.yaml` keeps `keep` and appends `demo` and `cmd`.
47. In **cwd-init** after 12: `skl init --from acme/skl-config:teams/platform.yaml` exits non-zero; YAML still has the two packages from 12.

Interactive-only behaviour (TTY menu, `--ns` prompt, docs “open?” prompt, spinner) is **not** asserted in smoke; unit-test those branches with fake TTY flags instead.

Run `zig build` and `./scripts/smoke-tests.sh` on the host OS. Also `./scripts/smoke-tests.sh --binary` after a release-layout binary exists (or skip `--binary` until step 14 if `bin/` is empty — then the default in-tree binary must still pass). Step 14’s **release** workflow runs `--binary` on Linux, macOS, and Windows against each shipped artifact; the script must already be portable (Git Bash on Windows).

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Added `scripts/smoke-tests.sh` (scenarios 1–47, fail-fast) and `scripts/test-everything.sh` (`zig build`, `zig build test`, then smoke). Each run uses a throwaway `HOME` (`mktemp` + `pwd -P`), several project cwds, and fixture remotes under `$HOME/remotes` named `acme/*.git`. Fixture `git init` / `add` / `commit` / `config` always set `GIT_DIR` and `GIT_WORK_TREE` to that path and abort if `git rev-parse --show-toplevel` is not it. `skl` is invoked with those unset, `GIT_CONFIG_GLOBAL` pointing at the throwaway gitconfig, and `insteadOf` rewriting `git@github.com:` / `git@github.example.com:` to `file://` remotes. `SKL_BROWSER` is a stub that logs argv.

`--binary` selects `bin/<arch>/<os>/skl`. Default is `zig-out/bin/skl`.

`git show -- <ref>:<path>` does not read the blob (git treats the spec as a pathspec). `showFile` now runs `git show <ref>:<path>`; ref and path are already validated. After scenario 19 the same owner/repo exists on two hosts, so remove/update/docs queries use namespace `demo` instead of `acme/skills`. After `init -g --from` (13), the harness restores global `packages: []` so scenario 22 can `-g add --ns demo`.
