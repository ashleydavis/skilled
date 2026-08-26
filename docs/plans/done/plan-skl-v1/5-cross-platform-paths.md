# 5. Cross-platform paths

## Goal

Resolve home, config, store, and agent skill/command directories the same way on Linux, macOS, and Windows.

## Files

- `src/lib/paths.zig` + `src/lib/paths.test.zig`
- Re-export from `src/lib/lib.zig`. Wire `test { _ = @import("paths.test.zig"); }`.

## Rules

- **Home:** `HOME`, else `USERPROFILE` (Windows).
- **Config file:** `$XDG_CONFIG_HOME/skilled/skl.yaml` if `XDG_CONFIG_HOME` is set, else `<home>/.config/skilled/skl.yaml` on **all** platforms (Windows included) so a stow-managed `~/.config` tree works.
- **Store root:** `<home>/.skilled/store` on purpose — v1 does **not** honour `XDG_DATA_HOME`.
- **Project config:** `<cwd>/skl.yaml`.
- **Global agent roots:** `<home>/.cursor/skills`, `<home>/.cursor/commands`, `<home>/.claude/skills`, `<home>/.claude/commands`.
- **Project agent roots:** `<cwd>/.cursor/skills`, `<cwd>/.cursor/commands`, `<cwd>/.claude/skills`, `<cwd>/.claude/commands`.
- **Never** write under `<home>/.cursor/skills-cursor/` (Cursor-managed).
- **Store clone path:** `<store>/<host>/<owner>/<repo>/` where `github.com` and `github.example.com` are ordinary directory names (valid on Linux, macOS, Windows).
- Use `std.fs.path` / `std.Io.Dir.path` separators.

`scopeFromFlag(global: bool, cwd)` returns a struct of config path + four agent roots.

## Tests

Unit-test path joins with a fake home/cwd:

- Home / config / store / agent roots.
- `XDG_CONFIG_HOME`.
- Windows `USERPROFILE` fake.
- Dotted host segment `github.example.com` in the store path.
- Store ignores `XDG_DATA_HOME`.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Added `src/lib/paths.zig` (with co-located tests) and re-exported it from `lib.zig`.

- Home is `HOME`, else `USERPROFILE`; empty values are treated as unset. Missing both is `HomeNotFound`.
- Global config is `$XDG_CONFIG_HOME/skilled/skl.yaml` when that env is non-empty, else `<home>/.config/skilled/skl.yaml` on every platform. Project config is `<cwd>/skl.yaml`.
- Store is `<home>/.skilled/store` only — `storeDir` takes home, not the environment, so `XDG_DATA_HOME` cannot affect it. Clone path is `<store>/<host>/<owner>/<repo>` with the host as one directory name (`github.example.com` stays dotted).
- `scopeFromFlag` returns config path plus the four Cursor/Claude skill and command roots. Extra arguments beyond the plan's `(global, cwd)`: allocator, home, and optional `XDG_CONFIG_HOME`, because global YAML and agent roots cannot be resolved from cwd alone. Agent roots are never `skills-cursor`.

Joins go through `files.joinPath` (`std.Io.Dir.path`) so separators match the host OS.

Also added a Style rule to `CLAUDE.md` / `AGENTS.md`: if-statement bodies go in braces on the following lines, never on the same line as `if`. Expanded the few first-party one-line `if`s in `paths.zig`, `term.zig`, and `progress.zig` to match. Vendored Commander/YAML still use one-line `if`s.

Not wired into `main` yet (CLI context is step 11). Smoke tests are step 13; not run. `zig build` and `zig build test` pass; the test count moved when `paths.test.zig` was added.
