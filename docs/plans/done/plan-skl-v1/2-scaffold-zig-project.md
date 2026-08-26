# 2. Scaffold the Zig project

## Goal

Create a Zig 0.16 project that builds a `skl` binary and a library, with co-located tests and a `release` step. Do not recreate `CLAUDE.md` or `AGENTS.md`.

## Files to create or change

- `mise.toml` — pin `zig = "0.16.0"`.
- `build.zig` — library module at `src/lib/lib.zig`; executable module at `src/main.zig` named `skl` that imports the library; `zig build test` runs both lib and exe tests; `zig build run`; `release` copies the optimised binary to `bin/<arch>/<os>/skl` (`.exe` on Windows), same layout as the sibling `what-changed` clone.
- `build.zig.zon` — package name `.skilled`, minimum Zig 0.16.0.
- `.gitignore` — include `zig-out/`, `.zig-cache/`, `bin/`.
- `src/lib/files.zig` + `src/lib/files.test.zig` — copy from the sibling `what-changed` clone (slim if needed). Keep `readFile`, `fileExists`, `describeError`, `MAX_FILE_BYTES`, and `TestIo`.
- `src/lib/lib.zig` — re-exports; `refAllDecls` so lib tests run.
- `src/lib/version.zig` — `pub const version = "0.0.1";`.
- `src/lib/version.test.zig` — `version` is non-empty and equals `0.0.1`.
- `src/main.zig` — `pub fn main(init: std.process.Init) u8` prints version and exits 0 (arena from `init.arena`, writers from `init.io`).
- `src/main.test.zig` — covers the version print path as far as it can without spawning the process if that is awkward; at minimum the file exists and is wired.
- `CLAUDE.md` and `AGENTS.md` — do **not** recreate. The only edit: fixture git in `scripts/smoke-tests.sh` may `init` / `add` / `commit` / `config` **only** inside `mktemp` dirs with `GIT_DIR` and `GIT_WORK_TREE` set to those dirs; abort if `git rev-parse --show-toplevel` is not that throwaway path. Never run those commands against this checkout. `skl` itself is invoked with `GIT_DIR` and `GIT_WORK_TREE` unset. Keep both files in lockstep.

## Zig 0.16

Zig 0.16 requires an `std.Io` on every filesystem call and on `std.process.run`. The CLI creates exactly one Io from `std.process.Init` in `main` and passes it; tests use `TestIo`. Do not call the old 0.14-style `std.fs` APIs that no longer compile.

## Test wiring

Each `.zig` file that has a sibling `*.test.zig` ends with:

```zig
test {
    _ = @import("….test.zig");
}
```

`lib.zig` also `refAllDecls` so lib tests run. Check that `zig build test` count moved when the new test files were added.

Every top-level declaration and struct field gets the fenced `//` comment style from `CLAUDE.md`.

## Tests

- `version.test.zig`: `version` string is non-empty / equals `0.0.1`.
- `files.test.zig`: keep or adapt the copied what-changed cases for `readFile`, `fileExists`, `describeError`, `TestIo`.
- `main.test.zig`: wire the exe test step so it actually runs.

Smoke tests do not exist yet; they are added in step 13. Until then, `zig build` and `zig build test` are the gate.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Scaffolded a Zig 0.16 project that builds `skl` and a `skilled` library module. Zig is pinned in `mise.toml` and invoked as `zig` through mise. `mise trust` was required once so the new `mise.toml` would load.

Files: `mise.toml`, `.gitignore` (`zig-out/`, `.zig-cache/`, `bin/`), `build.zig` (lib + `skl` exe + `run` + `test` + `release` to `bin/<arch>/<os>/skl`), `build.zig.zon` (`.skilled`, fingerprint `0xd495bf31c2cabee4`), `src/lib/{lib,files,version}.zig` and matching `*.test.zig`, `src/main.zig` + `src/main.test.zig`. `files.zig` is a slim of the sibling clone: kept `readFile`, `fileExists`, `describeError`, `MAX_FILE_BYTES` (16MiB, sized for YAML/markdown), `TestIo`, plus `TemporaryDir` / write helpers tests need. Scaffold `main` prints `0.0.1` and exits 0.

`CLAUDE.md` / `AGENTS.md` were not recreated. Git-in-scripts isolation was updated (throwaway `GIT_DIR` / `GIT_WORK_TREE`, abort if toplevel is not that path, unset those when invoking `skl`). A Tools section was added: Zig and other tools come from mise (`mise.toml`) and are invoked by name. Done-means is `zig build`, `zig build test`, and smoke tests. Both files stayed in lockstep.

`zig build` and `zig build test` pass: **14/14** tests (12 lib, 2 exe). Smoke tests are step 13; not run.
