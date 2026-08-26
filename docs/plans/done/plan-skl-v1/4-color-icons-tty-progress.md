# 4. Color, icons, TTY, progress

## Goal

Detect whether color/icons and interactive prompts should run, and write clone/link progress to stderr only.

## Files

- `src/lib/term.zig` + `src/lib/term.test.zig`
- `src/lib/progress.zig` + `src/lib/progress.test.zig`
- Re-export from `src/lib/lib.zig`. Wire `test { _ = @import("….test.zig"); }` in each code file.

## `term.zig`

`pub const Style` holds whether color/icons are enabled.

`detectStyle(args, env, stdout_is_tty)` turns color **off** when any of:

- `--no-color`
- env `NO_COLOR` set (any value)
- env `SKL_NO_COLOR=1`
- stdout is not a TTY

Icons (Unicode: check, cross, arrow, package) are off whenever color is off.

`pub fn nonInteractive(args, env, stdin_is_tty)` is true when `--non-interactive` / `-n`, env `SKL_NONINTERACTIVE=1`, or stdin is not a TTY.

## `progress.zig`

`Progress` writes a single-line spinner/step text to **stderr** during clone/link (`Cloning owner/repo…`, `Linking ns/name…`) and clears the line on finish.

- Takes `*std.Io.Writer` (stderr), not a hidden handle.
- No-op when non-interactive, stderr is not a TTY, or color/style is disabled.
- Never write progress to stdout.

## Tests

- `detectStyle`: default TTY on; `--no-color`; `NO_COLOR`; `SKL_NO_COLOR`; non-TTY.
- `nonInteractive`: flag, env, non-TTY stdin.
- `progress`: no-op when disabled; writes to a buffer when enabled.

Unit-test against fake env/args and a buffer writer. Interactive spinner behaviour is not asserted in smoke tests (those come in step 13).

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Added `src/lib/term.zig` and `src/lib/progress.zig` (with co-located tests) and re-exported both from `lib.zig`.

- `detectStyle` turns color and icons off for `--no-color`, any `NO_COLOR`, `SKL_NO_COLOR=1`, or a non-TTY stdout. Icons stay in lockstep with color; Style methods return Unicode marks or ASCII stand-ins.
- `nonInteractive` is true for `--non-interactive` / `-n`, `SKL_NONINTERACTIVE=1`, or a non-TTY stdin.
- `Progress` takes a `*std.Io.Writer` (stderr in the CLI, a buffer in tests). It writes a single-line spinner plus `Cloning owner/repo…` / `Linking ns/name…` and clears the line on finish. It is a no-op when style is off, the run is non-interactive, or stderr is not a TTY. Writes are swallowed so a broken pipe cannot fail the clone.

Not wired into `main` yet (CLI context is step 11). Smoke tests are step 13; not run. `zig build` and `zig build test` pass; the test count moved when these files were added.
