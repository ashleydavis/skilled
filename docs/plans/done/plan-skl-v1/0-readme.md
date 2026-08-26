# 0. README

## Goal

Create `README.md` from the v1 design so this repo has user documentation before any Zig code exists. Ask the user for the `gh` install one-liner rather than inventing one. If this step edits `CLAUDE.md`, edit `AGENTS.md` to match.

## Files

- `README.md` (create).
- `CLAUDE.md` / `AGENTS.md` only if a README-related rule change is required; keep them in lockstep.

## Contents

- What `skl` is.
- Store / YAML / symlink layers.
- Package layout (`skills/` one-level `SKILL.md`, `commands/` recursive `.md`).
- YAML example with generic `acme` names only.
- Command table (`init`, `install`/`i`, `add`, `remove`, `update`, `list`, `docs`, `help`, `version`). `help` / `version` are the same as `--help` / `--version`.
- `--from` for a config file inside a git repo, including colon-split rules and that a blob `<ref>` is read via `git show` (not “whatever is on the default branch”). `init --from` creates `skl.yaml`; `add --from` appends into an existing file.
- `-g`; `--ns`; `--non-interactive`; `--no-color` / `NO_COLOR`.
- `SKL_BROWSER` (optional; overrides `xdg-open` / `open` / `cmd start`).
- `XDG_CONFIG_HOME` for the config path.
- Store is `~/.skilled/store` (not `XDG_DATA_HOME`).
- SSH requirement.
- Namespace uniqueness per config file.
- Missing-config → run `skl init`.
- Stow-safe config writes (without mentioning any personal tools repo).
- Windows Developer Mode for symlinks.
- Build/test commands (as they will be: `zig build`, `zig build test`, `./scripts/smoke-tests.sh --binary`).
- Placeholder for install-from-Pages until the user supplies the `gh` one-liner.

Do not put GitHub usernames in the README. Do not invent a `gh` install one-liner; ask the user.

There is no Zig project yet. Do not require `zig build`.

## Verify

- `README.md` exists and covers the contents list above.
- `rg` **product paths** (`README.md`, `CLAUDE.md`, `AGENTS.md`) for real company, department, or team names — no matches (generic `acme` examples only). Exclude `docs/plans/`. `CLAUDE.md` and `AGENTS.md` stay in lockstep if either was edited.

## Summary

Created `README.md` covering the v1 design before any Zig sources exist: what `skl` is; store / YAML / symlink layers; package layout; an `acme` YAML example; command table; `--from` colon-split rules and `git show` for blob refs; flags and env (`-g`, `--ns`, `--non-interactive`, `--no-color` / `NO_COLOR`, `SKL_BROWSER`, `XDG_CONFIG_HOME`); store path vs `XDG_DATA_HOME`; SSH; namespace uniqueness; missing-config; stow-safe writes; Windows Developer Mode; planned `zig build` / `zig build test` / `./scripts/smoke-tests.sh --binary`. Install-from-Pages is a placeholder (no invented `gh` one-liner; no GitHub usernames). `CLAUDE.md` and `AGENTS.md` were not edited. `zig build` was not run (no Zig project yet).
