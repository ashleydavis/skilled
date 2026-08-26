# 3. Vendor Commander and YAML, then extend Commander

## Goal

Copy Commander, YAML, and their dependencies from the sibling `what-changed` clone, then extend Commander with boolean flags, short flags, and root-option merge so `skl -g add` and `skl add -g` both work.

## Files to copy (smallest set that compiles)

From the sibling clone:

- `commander.zig` + `commander.test.zig`
- `yaml.zig` + `yaml.test.zig`
- `value.zig` + `value.test.zig` (YAML depends on it)
- `failure.zig` + `failure.test.zig` (YAML depends on it)

Place them under `src/lib/` (or the same layout what-changed uses, as long as `lib.zig` re-exports them). Wire each with `test { _ = @import("….test.zig"); }`. Keep the Commander help layout and error types (`Displayed`, `Refused`).

## Do not reimplement

Vendored Commander **already has** value options (`--ns <namespace>`), `--help`, and `--version`. Version flags are `-V, --version`. Do not take a registry or HTTP dependency.

Also accept the command names `help` and `version` as aliases of `--help` and `--version` (same `Displayed` / version print, exit 0). `help` / `version` are not unknown commands.

It is **missing on purpose** today: boolean flags, short flags, and `.opts()` inheritance.

## Extend `Command` (tested separately)

1. **Boolean flags.** If the flags string has no `<placeholder>`, the option takes no value. Presence stores `"true"`; absence is `null` (unless a default is set). v1 booleans: `--global` / `-g`, `--no-color`, `--non-interactive` / `-n`, `--open`. `--no-color` is its own flag, not a negatable `--color`.
2. **Short flags.** Parse `-g`, `-n`, `-h`, `-V` from a flags string like `"-g, --global"`. Clustering (`-gn`) is out of scope.
3. **Root-option merge.** Today, options collected before a subcommand name are discarded when descending. Change that: merge the parent's collected values into the child (the omitted `.opts()` inheritance). Unknown options on a subcommand also look up the parent chain. Declare `--global/-g`, `--no-color`, `--non-interactive/-n` once on the root. Both `skl -g add` and `skl add -g` then work.

Command-specific value/boolean options stay on that command only: `--ns <namespace>` on `add`, `--from <spec>` on `init` and `add`, `--open` on `docs`. `--help` / `--version` stay the existing Commander builtins. `help` and `version` as command names are aliases of those flags.

`--ns` is a value option (already supported), not a boolean. `--open` is docs-only, not a general Command boolean.

## Tests

Keep existing what-changed Commander/YAML/value/failure cases, plus:

- Boolean presence/absence.
- `-g` combined with `--ns <value>` on `add`.
- Prefix `skl -g add` and suffix `skl add -g` both set global.
- Unknown options still `Refused`.
- Help still `Displayed` (`--help`, `-h`, and the `help` command).
- `version` command prints the same as `--version` / `-V`.
- `--ns` still requires a value (it is not a boolean).
- `--open` is a boolean (no value).

Confirm the test count moved. Call through the module (`commander.parse(...)`, not a bare `parse(...)`).

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Copied Commander, YAML, `value`, and `failure` (with tests) from the sibling clone into `src/lib/` and re-exported them from `lib.zig`. Then extended Commander:

- Boolean flags: no `<placeholder>` means presence stores `"true"`, absence is null unless a default is set (`-g` / `--global`, `--no-color`, `-n` / `--non-interactive`, `--open`). `--no-color` is its own flag.
- Short flags: `"-g, --global"` parses as `-g` and `--global`; the option name is the long form. Clustering (`-gn`) is still out of scope.
- Root-option merge: values collected before a subcommand are kept, and unknown options walk the parent chain, so `skl -g add` and `skl add -g` both set global. `--ns` stays a value option; `--open` stays docs-only.
- `help` and `version` as command names match `--help` / `--version` (and `-h` / `-V`).

Sibling product strings in failure/YAML messages and comments were retargeted to this tool. Existing Commander parse/help cases were kept, plus skl-shaped tests for the new flags. `CLAUDE.md` / `AGENTS.md` gained a rule against snapshot values in docs.

`zig build` and `zig build test` pass; the test count moved when the vendored files and new Commander cases were added. Smoke tests are step 13; not run.
