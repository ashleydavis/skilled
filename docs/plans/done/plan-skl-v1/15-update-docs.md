# 15. Update docs

## Goal

Reconcile **all product docs** with the CLI that steps 1–14 actually shipped — not only `README.md`. Ask the user for the `gh` install one-liner if it is still a placeholder. If this step edits `CLAUDE.md`, edit `AGENTS.md` to match.

## Files

- `README.md` (install, getting started, development; created in step 0).
- `docs/HOW_IT_WORKS.md` (store, config, package layout, Git/SSH, Windows).
- `docs/COMMANDS.md` (command table, flags, `--from`).
- Any other product docs under `docs/` except `docs/plans/`.
- `CLAUDE.md` / `AGENTS.md` if a docs-related rule change is required; keep them in lockstep.

## What to check

Match the implemented binary and smoke tests. Spread the checks across the files that own each topic (README stays slim; `HOW_IT_WORKS.md` is architecture; `COMMANDS.md` is the CLI reference):

- Command table still matches `skl --help` / `skl help` (`init`, `install`/`i`, `add`, `remove`, `update`, `list`, `docs`, `help`, `version`). `skl version` matches `--version` / `-V`.
- Flags and env vars that exist in code: `-g`, `--ns`, `--non-interactive` / `-n`, `--no-color` / `NO_COLOR`, `SKL_NONINTERACTIVE`, `SKL_BROWSER`, `XDG_CONFIG_HOME`.
- `--from` colon-split rules and `git show` for blob `<ref>`. `init --from` creates; `add --from` appends and keeps existing packages.
- Store path `~/.skilled/store` (not `XDG_DATA_HOME`).
- SSH-only remotes; namespace uniqueness; missing-config → `skl init`.
- Stow-safe writes (no personal tools repo named).
- Windows Developer Mode for symlinks.
- Build/test commands that actually work.
- Install-from-Pages: keep a placeholder or insert the user’s `gh` one-liner if they have given it.

Do not put GitHub usernames in product docs except the real example repos Getting Started already uses. Do not invent a `gh` install one-liner; ask the user.

## Verify

After updating:

- `zig build` and `zig build test` still pass.
- `./scripts/smoke-tests.sh --binary` still passes.
- `rg` **product paths** (`src/`, `scripts/`, `README.md`, `docs/` excluding `docs/plans/`, `CLAUDE.md`, `AGENTS.md`, `.github/`) for real company, department, or team names — no matches (generic `acme` examples only; Getting Started may use the published example repos). `CLAUDE.md` and `AGENTS.md` are identical in substance.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Reconciled README, `docs/HOW_IT_WORKS.md`, and `docs/COMMANDS.md` with the shipped CLI: development commands include `zig build`, unit tests, both smoke invocations, and `test-everything.sh`; architecture spells out store vs `XDG_DATA_HOME`, missing-config, and `skills-cursor`; command reference documents github.com-only `owner/repo` matching and `git show <ref>:<path>` (no `--`, which would make git treat the spec as a pathspec). The user’s `gh` install one-liners in README were left as they were. `CLAUDE.md` / `AGENTS.md` needed no docs-rule change.
